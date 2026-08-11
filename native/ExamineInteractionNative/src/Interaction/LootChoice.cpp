#include "LootChoice.hpp"

#include "../Engine/Addresses.hpp"
#include "../Engine/Logging.hpp"

#include <RED4ext/Scripting/Natives/Generated/game/interactions/Choice.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/interactions/LootChoiceActionWrapper.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/Object.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>

#include <Windows.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>

namespace ExamineInteractionNative::Interaction
{
namespace
{
using LootChoice = RED4ext::game::interactions::LootChoiceActionWrapper;
using Choice = RED4ext::game::interactions::Choice;
using BuildLootChoice = Choice* (*)(LootChoice*, Choice*);
using SerializableHandle = RED4ext::Handle<RED4ext::ISerializable>;
using BuildPublisherChoiceEvent = void (*)(SerializableHandle*, Choice*, uint32_t*);
using PublishInteractionEvent = void (*)(void*, SerializableHandle*, void*, void*, void*);

struct PublisherBridge
{
    BuildPublisherChoiceEvent buildEvent{};
    PublishInteractionEvent publish{};
};

struct PublishContext
{
    void* hotspot{};
    uint64_t hotspotEntityID{};
    void* publisher{};
    void* layer{};
    void* activator{};
    std::chrono::steady_clock::time_point capturedAt{};
    uint64_t sequence{};
};

PublishInteractionEvent g_publishInteractionOriginal{};
void* g_publishInteractionAddress{};
std::mutex g_publishContextsMutex;
std::array<PublishContext, 256> g_publishContexts{};
size_t g_nextPublishContext{};
std::atomic_uint64_t g_publishContextSequence{};
thread_local bool g_isReplayingChoice{};

template<size_t N>
bool SignatureMatches(uintptr_t aAddress, const std::array<uint8_t, N>& aSignature)
{
    const auto* bytes = reinterpret_cast<const uint8_t*>(aAddress);
    return std::equal(aSignature.begin(), aSignature.end(), bytes);
}

uint64_t GetEntityID(void* aObject)
{
    return aObject ? reinterpret_cast<RED4ext::game::Object*>(aObject)->entityID.hash : 0;
}

bool IsLivePublishContext(const PublishContext& aContext)
{
    if (!aContext.hotspot || !aContext.publisher || !aContext.layer || !aContext.activator)
    {
        return false;
    }

    const auto hotspot = reinterpret_cast<uintptr_t>(aContext.hotspot);
    const auto layer = reinterpret_cast<uintptr_t>(aContext.layer);
    const auto activator = reinterpret_cast<uintptr_t>(aContext.activator);
    return *reinterpret_cast<void* const*>(
               hotspot + Addresses::InteractionHotspotSelfHandleOffset) == aContext.hotspot &&
           *reinterpret_cast<void* const*>(
               layer + Addresses::InteractionLayerSelfHandleOffset) == aContext.layer &&
           *reinterpret_cast<void* const*>(
               activator + Addresses::InteractionActivatorSelfHandleOffset) == aContext.activator;
}

void CapturePublishContext(void* aPublisher, void* aHotspot, void* aLayer, void* aActivator)
{
    if (g_isReplayingChoice || !aPublisher || !aHotspot || !aLayer || !aActivator)
    {
        return;
    }

    PublishContext context{
        aHotspot,
        *reinterpret_cast<const uint64_t*>(
            reinterpret_cast<uintptr_t>(aHotspot) + Addresses::InteractionHotspotEntityIDOffset),
        aPublisher,
        aLayer,
        aActivator,
        std::chrono::steady_clock::now(),
        ++g_publishContextSequence,
    };

    std::scoped_lock lock(g_publishContextsMutex);
    for (auto& existing : g_publishContexts)
    {
        if (existing.hotspot == aHotspot)
        {
            existing = context;
            return;
        }
    }

    g_publishContexts[g_nextPublishContext] = context;
    g_nextPublishContext = (g_nextPublishContext + 1) % g_publishContexts.size();
}

bool FindPublishContext(void* aOwner, PublishContext& aResult)
{
    constexpr auto maxAge = std::chrono::minutes(5);
    const auto now = std::chrono::steady_clock::now();
    const auto entityID = GetEntityID(aOwner);
    PublishContext* best{};

    std::scoped_lock lock(g_publishContextsMutex);
    for (auto& context : g_publishContexts)
    {
        if (context.hotspotEntityID != entityID)
        {
            continue;
        }

        if (now - context.capturedAt > maxAge || !IsLivePublishContext(context))
        {
            context = {};
            continue;
        }

        if (!best || context.sequence > best->sequence)
        {
            best = &context;
        }
    }

    if (best)
    {
        aResult = *best;
        *best = {};
        return true;
    }
    return false;
}

void PublishInteractionHook(void* aPublisher, SerializableHandle* aEvent,
                            void* aHotspot, void* aLayer, void* aActivator)
{
    CapturePublishContext(aPublisher, aHotspot, aLayer, aActivator);
    if (g_publishInteractionOriginal)
    {
        g_publishInteractionOriginal(aPublisher, aEvent, aHotspot, aLayer, aActivator);
    }
}

BuildLootChoice ResolveBuildLootChoice()
{
    static BuildLootChoice resolved = []() -> BuildLootChoice {
        const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        if (!moduleBase)
        {
            Logging::Error("Loot-choice bridge unavailable: game module base is missing.");
            return nullptr;
        }

        const auto address = moduleBase + Addresses::BuildLootChoiceOffset;
        if (!SignatureMatches(address, Addresses::BuildLootChoiceSignature))
        {
            Logging::Error("Loot-choice bridge disabled: builder signature mismatch.");
            return nullptr;
        }

        return reinterpret_cast<BuildLootChoice>(address);
    }();

    return resolved;
}

PublisherBridge ResolvePublisherBridge()
{
    static PublisherBridge resolved = []() -> PublisherBridge {
        const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        if (!moduleBase)
        {
            Logging::Error("Interaction publisher unavailable: game module base is missing.");
            return {};
        }

        const auto buildAddress = moduleBase + Addresses::BuildPublisherChoiceEventOffset;
        const auto publishAddress = moduleBase + Addresses::PublishInteractionEventOffset;
        if (!SignatureMatches(buildAddress, Addresses::BuildPublisherChoiceEventSignature) ||
            !SignatureMatches(publishAddress, Addresses::PublishInteractionEventSignature))
        {
            Logging::Error("Interaction publisher disabled: signature mismatch.");
            return {};
        }

        return {
            reinterpret_cast<BuildPublisherChoiceEvent>(buildAddress),
            reinterpret_cast<PublishInteractionEvent>(publishAddress),
        };
    }();

    return resolved;
}
}

bool Attach()
{
    const auto* sdk = Logging::g_sdk;
    const auto handle = Logging::g_pluginHandle;
    const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    if (!sdk || !sdk->hooking || !handle || !moduleBase)
    {
        Logging::Error("Interaction context bridge unavailable: RED4ext hooking API or game module base is missing.");
        return false;
    }

    const auto bridge = ResolvePublisherBridge();
    if (!bridge.buildEvent || !bridge.publish)
    {
        return false;
    }

    g_publishInteractionAddress = reinterpret_cast<void*>(
        moduleBase + Addresses::PublishInteractionEventOffset);
    if (!sdk->hooking->Attach(handle, g_publishInteractionAddress,
                              reinterpret_cast<void*>(&PublishInteractionHook),
                              reinterpret_cast<void**>(&g_publishInteractionOriginal)))
    {
        g_publishInteractionAddress = nullptr;
        Logging::Error("Interaction context bridge hook failed.");
        return false;
    }

    return true;
}

void Detach()
{
    const auto* sdk = Logging::g_sdk;
    const auto handle = Logging::g_pluginHandle;
    if (sdk && sdk->hooking && handle && g_publishInteractionAddress &&
        g_publishInteractionOriginal)
    {
        sdk->hooking->Detach(handle, g_publishInteractionAddress);
    }

    g_publishInteractionOriginal = nullptr;
    g_publishInteractionAddress = nullptr;
    std::scoped_lock lock(g_publishContextsMutex);
    g_publishContexts = {};
    g_nextPublishContext = 0;
    g_publishContextSequence.store(0);
}

bool PrepareLootChoiceEvent(
    const RED4ext::Handle<RED4ext::game::interactions::ChoiceEvent>& aEvent,
    RED4ext::ItemID aItemID, RED4ext::CName aAction,
    bool aRemoveItem, bool aIllegal)
{
    auto* event = aEvent.GetPtr();
    const auto builder = ResolveBuildLootChoice();
    if (!event || !builder || !aItemID.IsValid() || aAction.hash == 0)
    {
        return false;
    }

    LootChoice wrapper{};
    wrapper.removeItem = aRemoveItem;
    wrapper.itemId = aItemID;
    wrapper.action = aAction;
    builder(&wrapper, &event->choice);
    return true;
}

bool PublishLootChoiceEvent(
    const RED4ext::Handle<RED4ext::game::interactions::ChoiceEvent>& aEvent,
    int32_t aChoiceIndex)
{
    auto* event = aEvent.GetPtr();
    const auto bridge = ResolvePublisherBridge();
    if (!event || !bridge.buildEvent || !bridge.publish || aChoiceIndex < 0)
    {
        return false;
    }

    auto hotspot = event->hotspot.Lock();
    PublishContext context;
    if (!hotspot || !FindPublishContext(hotspot.GetPtr(), context))
    {
        Logging::Info("Vanilla loot interaction context unavailable for owner entityID=0x%llX.",
                      static_cast<unsigned long long>(GetEntityID(hotspot.GetPtr())));
        return false;
    }

    SerializableHandle publisherEvent;
    auto choiceIndex = static_cast<uint32_t>(aChoiceIndex);
    bridge.buildEvent(&publisherEvent, &event->choice, &choiceIndex);
    if (!publisherEvent)
    {
        Logging::Info("The vanilla PublisherChoiceEvent could not be constructed.");
        return false;
    }

    g_isReplayingChoice = true;
    bridge.publish(context.publisher, &publisherEvent, context.hotspot,
                   context.layer, context.activator);
    g_isReplayingChoice = false;
    return true;
}
}

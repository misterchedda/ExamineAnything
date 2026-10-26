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
#include <memory>
#include <unordered_map>
#include <RED4ext/Memory/SharedPtr.hpp>

namespace ExamineInteractionNative::Interaction
{
namespace
{
using LootChoice = RED4ext::game::interactions::LootChoiceActionWrapper;
using Choice = RED4ext::game::interactions::Choice;
using BuildLootChoice = Choice* (*)(LootChoice*, Choice*);
using SerializableHandle = RED4ext::Handle<RED4ext::ISerializable>;
using BuildPublisherChoiceEvent = SerializableHandle* (*)(SerializableHandle*, Choice*, uint32_t*);
using PublishInteractionEvent = void (*)(void*, SerializableHandle*, void*, void*, void*);

struct PublisherBridge
{
    BuildPublisherChoiceEvent buildEvent{};
    PublishInteractionEvent publish{};
};

struct PublishContext
{
    RED4ext::WeakPtr<void> hotspot;
    uint64_t hotspotEntityID{};
    void* publisher{};
    RED4ext::WeakHandle<RED4ext::ISerializable> layer;
    RED4ext::WeakPtr<void> activator;
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

// CHotSpot/CActivator use AtomicSharedStorage, not ISerializable handles.
// Release through the game's verified shared-storage destructor.
using ReleaseInteractionReference = void (*)(void*);
ReleaseInteractionReference g_releaseInteractionReference{};
struct NativeInteractionReference
{
    void* instance{};
    RED4ext::RefCnt* refCount{};
    explicit NativeInteractionReference(const RED4ext::WeakPtr<void>& aWeak)
    {
        if (aWeak.refCount && aWeak.refCount->IncRefIfNotZero())
        {
            instance = aWeak.instance;
            refCount = aWeak.refCount;
        }
    }
    NativeInteractionReference(const NativeInteractionReference&) = delete;
    ~NativeInteractionReference()
    {
        if (refCount) g_releaseInteractionReference(this);
    }
};
static_assert(sizeof(NativeInteractionReference) == 0x10);
struct PendingContext
{
    std::shared_ptr<NativeInteractionReference> hotspot;
    std::shared_ptr<NativeInteractionReference> activator;
    SerializableHandle event; // Keep the key unique if an engine queue is discarded.
};
using ProcessPublishRequest = void (*)(void*, void*);
ProcessPublishRequest g_processPublishOriginal{};
void* g_processPublishAddress{};
std::mutex g_pendingMutex;
std::unordered_map<void*, PendingContext> g_pendingContexts;
struct PreparedContext
{
    void* publisher{};
    uint64_t ownerID{};
    PendingContext retained;
    SerializableHandle layer;
};
std::unordered_map<void*, PreparedContext> g_preparedContexts;


void ProcessPublishRequestHook(void* aPublisher, void* aRequest)
{
    // The request owns its event at +0, but only weakly owns the hotspot.
    auto* event = *reinterpret_cast<void**>(aRequest);
    PendingContext retained;
    {
        std::scoped_lock lock(g_pendingMutex);
        auto it = g_pendingContexts.find(event);
        if (it != g_pendingContexts.end())
        {
            retained = std::move(it->second);
            g_pendingContexts.erase(it);
        }
    }
    g_processPublishOriginal(aPublisher, aRequest);
    if (retained.hotspot)
        Logging::Diagnostic("Vanilla loot success notification processed.");
    // Release only after the original processor has finished using the hotspot.
}

void CapturePublishContext(void* aPublisher, void* aHotspot, void* aLayer, void* aActivator)
{
    if (g_isReplayingChoice || !aPublisher || !aHotspot || !aLayer || !aActivator)
    {
        return;
    }

    PublishContext context;
    context.hotspot = *reinterpret_cast<RED4ext::WeakPtr<void>*>(
        reinterpret_cast<uintptr_t>(aHotspot) + Addresses::InteractionHotspotSelfHandleOffset);
    context.hotspotEntityID = *reinterpret_cast<const uint64_t*>(
        reinterpret_cast<uintptr_t>(aHotspot) + Addresses::InteractionHotspotEntityIDOffset);
    context.publisher = aPublisher;
    context.layer = *reinterpret_cast<RED4ext::WeakHandle<RED4ext::ISerializable>*>(
        reinterpret_cast<uintptr_t>(aLayer) + Addresses::InteractionLayerSelfHandleOffset);
    context.activator = *reinterpret_cast<RED4ext::WeakPtr<void>*>(
        reinterpret_cast<uintptr_t>(aActivator) + Addresses::InteractionActivatorSelfHandleOffset);
    context.capturedAt = std::chrono::steady_clock::now();
    context.sequence = ++g_publishContextSequence;

    std::scoped_lock lock(g_publishContextsMutex);
    for (auto& existing : g_publishContexts)
    {
        if (existing.hotspot.instance == aHotspot)
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

        if (now - context.capturedAt > maxAge)
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
    if (!Addresses::LootHooksVerified) return nullptr;
    static BuildLootChoice resolved = []() -> BuildLootChoice {
        const auto address = RED4ext::UniversalRelocBase::Resolve(Addresses::BuildLootChoice);
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
    if (!Addresses::LootHooksVerified) return {};
    static PublisherBridge resolved = []() -> PublisherBridge {
        const auto buildAddress = RED4ext::UniversalRelocBase::Resolve(Addresses::BuildPublisherChoiceEvent);
        const auto publishAddress = RED4ext::UniversalRelocBase::Resolve(Addresses::PublishInteractionEvent);
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
    if (!sdk || !sdk->hooking || !handle)
    {
        Logging::Error("Interaction context bridge unavailable: RED4ext hooking API is missing.");
        return false;
    }

    const auto bridge = ResolvePublisherBridge();
    if (!bridge.buildEvent || !bridge.publish)
    {
        return false;
    }

    const auto processAddress = RED4ext::UniversalRelocBase::Resolve(Addresses::ProcessPublishRequest);
    const auto releaseAddress = RED4ext::UniversalRelocBase::Resolve(Addresses::ReleaseInteractionReference);
    if (!SignatureMatches(processAddress, Addresses::ProcessPublishRequestSignature) ||
        !SignatureMatches(releaseAddress, Addresses::ReleaseInteractionReferenceSignature))
    {
        Logging::Error("Loot publication lifetime bridge disabled: signature mismatch.");
        return false;
    }
    g_releaseInteractionReference = reinterpret_cast<ReleaseInteractionReference>(releaseAddress);
    g_processPublishAddress = reinterpret_cast<void*>(processAddress);
    if (!sdk->hooking->Attach(handle, g_processPublishAddress,
                              reinterpret_cast<void*>(&ProcessPublishRequestHook),
                              reinterpret_cast<void**>(&g_processPublishOriginal)))
    {
        g_processPublishAddress = nullptr;
        Logging::Error("Loot publication lifetime hook failed.");
        return false;
    }

    g_publishInteractionAddress = reinterpret_cast<void*>(
        RED4ext::UniversalRelocBase::Resolve(Addresses::PublishInteractionEvent));
    if (!sdk->hooking->Attach(handle, g_publishInteractionAddress,
                              reinterpret_cast<void*>(&PublishInteractionHook),
                              reinterpret_cast<void**>(&g_publishInteractionOriginal)))
    {
        sdk->hooking->Detach(handle, g_processPublishAddress);
        g_processPublishAddress = nullptr;
        g_processPublishOriginal = nullptr;
        g_publishInteractionAddress = nullptr;
        Logging::Error("Interaction context bridge hook failed.");
        return false;
    }

    Logging::Info("Vanilla loot publisher context hook attached (2.5).");
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

    if (sdk && sdk->hooking && handle && g_processPublishAddress)
        sdk->hooking->Detach(handle, g_processPublishAddress);
    g_processPublishAddress = nullptr;
    g_processPublishOriginal = nullptr;
    {
        std::scoped_lock lock(g_pendingMutex);
        g_pendingContexts.clear();
        g_preparedContexts.clear();
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
    if (!event || !builder || !g_processPublishOriginal || !g_releaseInteractionReference ||
        !aItemID.IsValid() || aAction.hash == 0)
    {
        return false;
    }

    auto owner = event->hotspot.Lock();
    PublishContext context;
    if (!owner || !FindPublishContext(owner.GetPtr(), context))
    {
        Logging::Info("Loot preparation failed: no native context before transfer.");
        return false;
    }
    PreparedContext prepared;
    prepared.publisher = context.publisher;
    prepared.ownerID = context.hotspotEntityID;
    prepared.retained.hotspot = std::make_shared<NativeInteractionReference>(context.hotspot);
    prepared.retained.activator = std::make_shared<NativeInteractionReference>(context.activator);
    prepared.layer = context.layer.Lock();
    if (!prepared.retained.hotspot->instance || !prepared.retained.activator->instance || !prepared.layer)
    {
        Logging::Info("Loot preparation failed: native context expired before transfer.");
        return false;
    }
    {
        std::scoped_lock lock(g_pendingMutex);
        g_preparedContexts.insert_or_assign(event, std::move(prepared));
    }

    LootChoice wrapper{};
    wrapper.removeItem = aRemoveItem;
    wrapper.itemId = aItemID;
    wrapper.action = aAction;
    builder(&wrapper, &event->choice);
    Logging::Diagnostic("Vanilla loot choice prepared: action=%llu.",
                  static_cast<unsigned long long>(aAction.hash));
    return true;
}

void CancelLootChoiceEvent(
    const RED4ext::Handle<RED4ext::game::interactions::ChoiceEvent>& aEvent)
{
    std::scoped_lock lock(g_pendingMutex);
    g_preparedContexts.erase(aEvent.GetPtr());
}

bool PublishLootChoiceEvent(
    const RED4ext::Handle<RED4ext::game::interactions::ChoiceEvent>& aEvent,
    int32_t aChoiceIndex)
{
    auto* event = aEvent.GetPtr();
    const auto bridge = ResolvePublisherBridge();
    if (!event || !bridge.buildEvent || !bridge.publish || !g_processPublishOriginal ||
        !g_releaseInteractionReference || aChoiceIndex < 0)
    {
        return false;
    }

    PreparedContext prepared;
    {
        std::scoped_lock lock(g_pendingMutex);
        auto it = g_preparedContexts.find(event);
        if (it == g_preparedContexts.end())
        {
            Logging::Info("Loot publication failed: prepared context unavailable.");
            return false;
        }
        prepared = std::move(it->second);
        g_preparedContexts.erase(it);
    }
    auto& retained = prepared.retained;

    SerializableHandle publisherEvent;
    auto choiceIndex = static_cast<uint32_t>(aChoiceIndex);
    bridge.buildEvent(&publisherEvent, &event->choice, &choiceIndex);
    if (!publisherEvent)
    {
        Logging::Info("The vanilla PublisherChoiceEvent could not be constructed.");
        return false;
    }

    retained.event = publisherEvent;
    {
        std::scoped_lock lock(g_pendingMutex);
        g_pendingContexts.emplace(publisherEvent.GetPtr(), retained);
    }
    g_isReplayingChoice = true;
    bridge.publish(prepared.publisher, &publisherEvent, retained.hotspot->instance,
                   prepared.layer.GetPtr(), retained.activator->instance);
    g_isReplayingChoice = false;
    Logging::Diagnostic("Vanilla loot success notification queued: owner=0x%llX choice=%u.",
                  static_cast<unsigned long long>(prepared.ownerID), choiceIndex);
    return true;
}
}

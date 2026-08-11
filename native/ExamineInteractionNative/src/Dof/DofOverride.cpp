#include "DofOverride.hpp"

#include "../Engine/Addresses.hpp"
#include "../Engine/Logging.hpp"

#include <RED4ext/RED4ext.hpp>

#include <Windows.h>

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace ExamineInteractionNative::Dof
{
namespace
{
constexpr uint32_t DepthOfFieldHookMask = 1u << 0;
constexpr uint32_t CombinedBlursHookMask = 1u << 1;

struct OverrideState
{
    std::atomic<bool> active{false};
    std::atomic<float> intensity{1.0f};
    std::atomic<float> nearBlur{-1.0f};
    std::atomic<float> nearFocus{-1.0f};
    std::atomic<float> farBlur{1.0f};
    std::atomic<float> farFocus{0.5f};
    std::atomic<bool> useNearPlane{false};
    std::atomic<bool> useFarPlane{true};
};

struct RenderStateBackup
{
    float intensity{};
    float nearBlur{};
    float nearFocus{};
    float farBlur{};
    float farFocus{};
    uint8_t useNearPlane{};
    uint8_t useFarPlane{};
    bool featureEnabled{};
};

using RenderNodeExecute = void (*)(void*, void*);

OverrideState s_override;
std::atomic<uint32_t> s_hookMask{};
uintptr_t s_gameModuleBase{};
RenderNodeExecute s_depthOfFieldSeparableOriginal{};
RenderNodeExecute s_combinedBlursOriginal{};

template<std::size_t N>
bool SignatureMatches(uintptr_t aAddress, const std::array<uint8_t, N>& aExpected)
{
    __try
    {
        return std::memcmp(reinterpret_cast<const void*>(aAddress), aExpected.data(), N) == 0;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool TrySetRenderFeature(void* aNodeContext, uint32_t aBit, bool aEnabled, bool& aPrevious)
{
    if (!aNodeContext)
    {
        return false;
    }

    __try
    {
        const auto context = reinterpret_cast<uintptr_t>(aNodeContext);
        if ((*reinterpret_cast<const uint8_t*>(context + 0x30) & 1u) != 0)
        {
            return false;
        }

        const auto renderState = *reinterpret_cast<uintptr_t*>(context + Addresses::RenderStateOffset);
        if (!renderState)
        {
            return false;
        }

        auto* word = reinterpret_cast<uint64_t*>(
            renderState + Addresses::RenderFeatureBitsOffset +
            static_cast<uintptr_t>(aBit >> 6u) * sizeof(uint64_t));
        const auto mask = uint64_t{1} << (aBit & 0x3Fu);
        aPrevious = (*word & mask) != 0;
        if (aEnabled)
        {
            *word |= mask;
        }
        else
        {
            *word &= ~mask;
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool TryApplyRenderState(void* aNodeContext, RenderStateBackup& aBackup)
{
    if (!aNodeContext)
    {
        return false;
    }

    __try
    {
        const auto context = reinterpret_cast<uintptr_t>(aNodeContext);
        const auto renderState = *reinterpret_cast<uintptr_t*>(context + Addresses::RenderStateOffset);
        if (!renderState)
        {
            return false;
        }

        auto* intensity = reinterpret_cast<float*>(renderState + Addresses::DofIntensityOffset);
        auto* nearBlur = reinterpret_cast<float*>(renderState + Addresses::DofNearBlurOffset);
        auto* nearFocus = reinterpret_cast<float*>(renderState + Addresses::DofNearFocusOffset);
        auto* farBlur = reinterpret_cast<float*>(renderState + Addresses::DofFarBlurOffset);
        auto* farFocus = reinterpret_cast<float*>(renderState + Addresses::DofFarFocusOffset);
        auto* useNearPlane = reinterpret_cast<uint8_t*>(renderState + Addresses::DofUseNearPlaneOffset);
        auto* useFarPlane = reinterpret_cast<uint8_t*>(renderState + Addresses::DofUseFarPlaneOffset);

        aBackup.intensity = *intensity;
        aBackup.nearBlur = *nearBlur;
        aBackup.nearFocus = *nearFocus;
        aBackup.farBlur = *farBlur;
        aBackup.farFocus = *farFocus;
        aBackup.useNearPlane = *useNearPlane;
        aBackup.useFarPlane = *useFarPlane;

        *intensity = s_override.intensity.load(std::memory_order_relaxed);
        *nearBlur = s_override.nearBlur.load(std::memory_order_relaxed);
        *nearFocus = s_override.nearFocus.load(std::memory_order_relaxed);
        *farBlur = s_override.farBlur.load(std::memory_order_relaxed);
        *farFocus = s_override.farFocus.load(std::memory_order_relaxed);
        *useNearPlane = s_override.useNearPlane.load(std::memory_order_relaxed) ? 1u : 0u;
        *useFarPlane = s_override.useFarPlane.load(std::memory_order_relaxed) ? 1u : 0u;
        return TrySetRenderFeature(aNodeContext, Addresses::DofSeparableFeatureBit, true,
                                   aBackup.featureEnabled);
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

void RestoreRenderState(void* aNodeContext, const RenderStateBackup& aBackup)
{
    if (!aNodeContext)
    {
        return;
    }

    __try
    {
        const auto context = reinterpret_cast<uintptr_t>(aNodeContext);
        const auto renderState = *reinterpret_cast<uintptr_t*>(context + Addresses::RenderStateOffset);
        if (!renderState)
        {
            return;
        }

        *reinterpret_cast<float*>(renderState + Addresses::DofIntensityOffset) = aBackup.intensity;
        *reinterpret_cast<float*>(renderState + Addresses::DofNearBlurOffset) = aBackup.nearBlur;
        *reinterpret_cast<float*>(renderState + Addresses::DofNearFocusOffset) = aBackup.nearFocus;
        *reinterpret_cast<float*>(renderState + Addresses::DofFarBlurOffset) = aBackup.farBlur;
        *reinterpret_cast<float*>(renderState + Addresses::DofFarFocusOffset) = aBackup.farFocus;
        *reinterpret_cast<uint8_t*>(renderState + Addresses::DofUseNearPlaneOffset) = aBackup.useNearPlane;
        *reinterpret_cast<uint8_t*>(renderState + Addresses::DofUseFarPlaneOffset) = aBackup.useFarPlane;
        bool ignored = false;
        TrySetRenderFeature(aNodeContext, Addresses::DofSeparableFeatureBit,
                            aBackup.featureEnabled, ignored);
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
    }
}

void DepthOfFieldSeparableHook(void* aParam1, void* aNodeContext)
{
    RenderStateBackup backup{};
    const bool patched = s_override.active.load(std::memory_order_acquire) &&
                         TryApplyRenderState(aNodeContext, backup);

    if (s_depthOfFieldSeparableOriginal)
    {
        s_depthOfFieldSeparableOriginal(aParam1, aNodeContext);
    }

    if (patched)
    {
        RestoreRenderState(aNodeContext, backup);
    }
}

void CombinedBlursHook(void* aParam1, void* aNodeContext)
{
    bool previous = false;
    const bool patched = s_override.active.load(std::memory_order_acquire) &&
                         TrySetRenderFeature(aNodeContext, Addresses::CombinedDofFeatureBit,
                                             true, previous);

    if (s_combinedBlursOriginal)
    {
        s_combinedBlursOriginal(aParam1, aNodeContext);
    }

    if (patched)
    {
        bool ignored = false;
        TrySetRenderFeature(aNodeContext, Addresses::CombinedDofFeatureBit, previous, ignored);
    }
}

template<std::size_t N>
bool AttachHook(const char* aName, uintptr_t aOffset,
                const std::array<uint8_t, N>& aSignature, void* aHook,
                void** aOriginal, uint32_t aMask)
{
    const auto* sdk = Logging::g_sdk;
    const auto handle = Logging::g_pluginHandle;
    if (!sdk || !sdk->hooking || !handle || !s_gameModuleBase)
    {
        Logging::Error("%s unavailable: RED4ext hooking API or game module base is missing.", aName);
        return false;
    }

    const auto address = s_gameModuleBase + aOffset;
    if (!SignatureMatches(address, aSignature))
    {
        Logging::Error("%s disabled: signature mismatch at module+0x%llX.", aName,
                       static_cast<unsigned long long>(aOffset));
        return false;
    }

    if (!sdk->hooking->Attach(handle, reinterpret_cast<void*>(address), aHook, aOriginal))
    {
        Logging::Error("%s attach failed at module+0x%llX.", aName,
                       static_cast<unsigned long long>(aOffset));
        return false;
    }

    s_hookMask.fetch_or(aMask, std::memory_order_relaxed);
    Logging::Info("Attached %s at module+0x%llX.", aName,
                  static_cast<unsigned long long>(aOffset));
    return true;
}
}

bool Attach()
{
    s_gameModuleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const bool separable = AttachHook(
        "native DOF separable override", Addresses::DepthOfFieldSeparableOffset,
        Addresses::DepthOfFieldSeparableSignature,
        reinterpret_cast<void*>(&DepthOfFieldSeparableHook),
        reinterpret_cast<void**>(&s_depthOfFieldSeparableOriginal), DepthOfFieldHookMask);
    const bool combined = AttachHook(
        "native combined-DOF compositor override", Addresses::CombinedBlursOffset,
        Addresses::CombinedBlursSignature, reinterpret_cast<void*>(&CombinedBlursHook),
        reinterpret_cast<void**>(&s_combinedBlursOriginal), CombinedBlursHookMask);
    return separable && combined;
}

void Detach()
{
    s_override.active.store(false, std::memory_order_release);
    const auto* sdk = Logging::g_sdk;
    const auto handle = Logging::g_pluginHandle;
    if (sdk && sdk->hooking && handle && s_gameModuleBase)
    {
        if ((s_hookMask.load(std::memory_order_relaxed) & CombinedBlursHookMask) != 0)
        {
            sdk->hooking->Detach(handle,
                reinterpret_cast<void*>(s_gameModuleBase + Addresses::CombinedBlursOffset));
        }
        if ((s_hookMask.load(std::memory_order_relaxed) & DepthOfFieldHookMask) != 0)
        {
            sdk->hooking->Detach(handle,
                reinterpret_cast<void*>(s_gameModuleBase + Addresses::DepthOfFieldSeparableOffset));
        }
    }

    s_hookMask.store(0, std::memory_order_relaxed);
    s_depthOfFieldSeparableOriginal = nullptr;
    s_combinedBlursOriginal = nullptr;
    s_gameModuleBase = 0;
}

bool Set(float aIntensity, float aNearBlur, float aNearFocus, float aFarBlur,
         float aFarFocus, bool aUseNearPlane, bool aUseFarPlane)
{
    const auto requiredHooks = DepthOfFieldHookMask | CombinedBlursHookMask;
    const bool ready = (s_hookMask.load(std::memory_order_acquire) & requiredHooks) == requiredHooks;
    if (!ready)
    {
        return false;
    }

    s_override.intensity.store(aIntensity, std::memory_order_relaxed);
    s_override.nearBlur.store(aNearBlur, std::memory_order_relaxed);
    s_override.nearFocus.store(aNearFocus, std::memory_order_relaxed);
    s_override.farBlur.store(aFarBlur, std::memory_order_relaxed);
    s_override.farFocus.store(aFarFocus, std::memory_order_relaxed);
    s_override.useNearPlane.store(aUseNearPlane, std::memory_order_relaxed);
    s_override.useFarPlane.store(aUseFarPlane, std::memory_order_relaxed);
    s_override.active.store(true, std::memory_order_release);
#if EXAMINE_INTERACTION_PROFILE_NATIVE
    Logging::Info("Native DOF override enabled: intensity=%.3f near=(%.3f, %.3f, %u) far=(%.3f, %.3f, %u).",
                  aIntensity, aNearBlur, aNearFocus, aUseNearPlane ? 1u : 0u,
                  aFarBlur, aFarFocus, aUseFarPlane ? 1u : 0u);
#endif
    return true;
}

bool Reset()
{
    [[maybe_unused]] const bool wasActive = s_override.active.exchange(false, std::memory_order_acq_rel);
#if EXAMINE_INTERACTION_PROFILE_NATIVE
    if (wasActive)
    {
        Logging::Info("Native DOF override released.");
    }
#endif
    return wasActive;
}
}

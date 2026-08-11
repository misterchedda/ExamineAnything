#pragma once

#include <RED4ext/Relocation.hpp>

#include <array>
#include <cstddef>
#include <cstdint>

namespace ExamineInteractionNative::Addresses
{
// Cyberpunk 2077 2.31, Cyberpunk2077.exe SHA-256: A7DE82945C03E041FC7339FCF9066224D98DB2F5D80FEA50F7947BB350A60991
inline constexpr uintptr_t DepthOfFieldSeparableOffset = 0x00CD037Cull;
inline constexpr uintptr_t CombinedBlursOffset = 0x0061DF5Cull;
inline constexpr uintptr_t BuildLootChoiceOffset = 0x024955A0ull;
inline constexpr uintptr_t BuildPublisherChoiceEventOffset = 0x00F9261Cull;
inline constexpr uintptr_t PublishInteractionEventOffset = 0x00722394ull;

inline constexpr ptrdiff_t InteractionHotspotEntityIDOffset = 0x08;
inline constexpr ptrdiff_t InteractionHotspotSelfHandleOffset = 0x30;
inline constexpr ptrdiff_t InteractionLayerSelfHandleOffset = 0x08;
inline constexpr ptrdiff_t InteractionActivatorSelfHandleOffset = 0x20;

inline constexpr ptrdiff_t RenderStateOffset = 0x18;
inline constexpr ptrdiff_t RenderFeatureBitsOffset = 0x17D0;
inline constexpr ptrdiff_t DofIntensityOffset = 0x16C8;
inline constexpr ptrdiff_t DofNearBlurOffset = 0x16CC;
inline constexpr ptrdiff_t DofNearFocusOffset = 0x16D0;
inline constexpr ptrdiff_t DofFarBlurOffset = 0x16D4;
inline constexpr ptrdiff_t DofFarFocusOffset = 0x16D8;
inline constexpr ptrdiff_t DofUseNearPlaneOffset = 0x16DC;
inline constexpr ptrdiff_t DofUseFarPlaneOffset = 0x16DD;
inline constexpr uint32_t DofSeparableFeatureBit = 5;
inline constexpr uint32_t CombinedDofFeatureBit = 17;

inline constexpr std::array<uint8_t, 10> DepthOfFieldSeparableSignature = {
    0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74, 0x24, 0x10,
};
inline constexpr std::array<uint8_t, 10> CombinedBlursSignature = {
    0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x08, 0x55, 0x56, 0x57,
};
inline constexpr std::array<uint8_t, 16> BuildLootChoiceSignature = {
    0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74,
    0x24, 0x10, 0x57, 0x48, 0x83, 0xEC, 0x40, 0x48,
};
inline constexpr std::array<uint8_t, 16> BuildPublisherChoiceEventSignature = {
    0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x08, 0x48,
    0x89, 0x68, 0x10, 0x48, 0x89, 0x70, 0x18, 0x57,
};
inline constexpr std::array<uint8_t, 16> PublishInteractionEventSignature = {
    0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83,
    0xEC, 0x70, 0x48, 0x8B, 0x84, 0x24, 0xA0, 0x00,
};

inline constexpr uint32_t WorldNodeInstanceSetVisibility = 2290487415u;
inline constexpr uint32_t RenderProxySetVisibility = 1790971865u;
inline constexpr uint32_t WorldNodeInstanceAttach = 3515291207u;
inline constexpr uint32_t WorldNodeInstanceDetach = 3473806907u;

inline constexpr ptrdiff_t WorldNodeDefinitionOffset = 0x60;
inline constexpr ptrdiff_t MeshRenderProxyOffset = 0xC8;
}

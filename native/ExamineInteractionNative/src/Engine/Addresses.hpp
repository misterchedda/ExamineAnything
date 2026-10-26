#pragma once

#include <RED4ext/Relocation.hpp>

#include <array>
#include <cstddef>
#include <cstdint>

namespace ExamineInteractionNative::Addresses
{
// Loot bridge addresses and context offsets verified against the 2.5 executable.
inline constexpr bool LootHooksVerified = true;
// Function IDs resolved by RED4ext; byte guards below validated against 2.5.
// 2.5 executable SHA-256: D36E74C47592E9C656AE250078CB40B2BE63C782AF5BFBEFF2280D43E653FAB4
inline constexpr uint32_t DepthOfFieldSeparable = 2839290562u;
inline constexpr uint32_t CombinedBlurs = 2519343054u;
inline constexpr uint32_t BuildLootChoice = 2024872126u;
inline constexpr uint32_t BuildPublisherChoiceEvent = 2877972209u;
inline constexpr uint32_t PublishInteractionEvent = 75584799u;

inline constexpr ptrdiff_t InteractionHotspotEntityIDOffset = 0x08;
inline constexpr ptrdiff_t InteractionHotspotSelfHandleOffset = 0x30;
inline constexpr ptrdiff_t InteractionLayerSelfHandleOffset = 0x08;
inline constexpr ptrdiff_t InteractionActivatorSelfHandleOffset = 0x20;

inline constexpr ptrdiff_t RenderStateOffset = 0x18;
inline constexpr ptrdiff_t RenderFeatureBitsOffset = 0x25B0;
inline constexpr ptrdiff_t DofIntensityOffset = 0x24B0;
inline constexpr ptrdiff_t DofNearBlurOffset = 0x24B4;
inline constexpr ptrdiff_t DofNearFocusOffset = 0x24B8;
inline constexpr ptrdiff_t DofFarBlurOffset = 0x24BC;
inline constexpr ptrdiff_t DofFarFocusOffset = 0x24C0;
inline constexpr ptrdiff_t DofUseNearPlaneOffset = 0x24C4;
inline constexpr ptrdiff_t DofUseFarPlaneOffset = 0x24C5;
inline constexpr uint32_t DofSeparableFeatureBit = 5;
inline constexpr uint32_t CombinedDofFeatureBit = 17;

inline constexpr std::array<uint8_t, 24> DepthOfFieldSeparableSignature = {
    0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74, 0x24, 0x10, 0x55, 0x57,
    0x41, 0x56, 0x48, 0x8D, 0x6C, 0x24, 0xB9, 0x48, 0x81, 0xEC, 0xF0, 0x00,
};
inline constexpr std::array<uint8_t, 24> CombinedBlursSignature = {
    0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x08, 0x55, 0x56, 0x57, 0x41, 0x54,
    0x41, 0x55, 0x41, 0x56, 0x41, 0x57, 0x48, 0x8D, 0x6C, 0x24, 0x90, 0x48,
};
inline constexpr std::array<uint8_t, 24> BuildLootChoiceSignature = {
    0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74, 0x24, 0x10, 0x57, 0x48,
    0x83, 0xEC, 0x40, 0x48, 0x8B, 0xF9, 0x48, 0x8B, 0xF2, 0x48, 0x8B, 0xCA,
};
inline constexpr std::array<uint8_t, 24> BuildPublisherChoiceEventSignature = {
    0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x08, 0x48, 0x89, 0x68, 0x10, 0x48,
    0x89, 0x70, 0x18, 0x57, 0x48, 0x83, 0xEC, 0x30, 0x48, 0x8B, 0xF2, 0x48,
};
inline constexpr std::array<uint8_t, 24> PublishInteractionEventSignature = {
    0x40, 0x53, 0x48, 0x83, 0xEC, 0x70, 0x48, 0x8B, 0x84, 0x24, 0xA0, 0x00,
    0x00, 0x00, 0x48, 0x8B, 0xD9, 0x48, 0x8D, 0x4C, 0x24, 0x30, 0x48, 0x89,
};

inline constexpr uint32_t ProcessPublishRequest = 887889579u;
inline constexpr std::array<uint8_t, 24> ProcessPublishRequestSignature = {
    0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x08, 0x48, 0x89, 0x70, 0x10, 0x48, 0x89, 0x78, 0x18, 0x55, 0x41, 0x56, 0x41, 0x57, 0x48, 0x8D, 0x68, 0xA1
};
inline constexpr uint32_t ReleaseInteractionReference = 3507299178u;
inline constexpr std::array<uint8_t, 24> ReleaseInteractionReferenceSignature = {
    0x40, 0x53, 0x48, 0x83, 0xEC, 0x30, 0x48, 0x8B, 0xD9, 0xE8, 0xDA, 0xBC, 0xA4, 0xFF, 0x84, 0xC0, 0x75, 0x06, 0x48, 0x83, 0xC4, 0x30, 0x5B, 0xC3
};

inline constexpr uint32_t WorldNodeInstanceSetVisibility = 2290487415u;
inline constexpr uint32_t RenderProxySetVisibility = 1790971865u;
inline constexpr uint32_t WorldNodeInstanceAttach = 3515291207u;
inline constexpr uint32_t WorldNodeInstanceDetach = 3473806907u;

inline constexpr ptrdiff_t WorldNodeDefinitionOffset = 0x60;
inline constexpr ptrdiff_t MeshRenderProxyOffset = 0xC8;
}

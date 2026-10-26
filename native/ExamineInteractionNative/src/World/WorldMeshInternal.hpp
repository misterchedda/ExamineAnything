#pragma once

#include "WorldMesh.hpp"

#include <RED4ext/Scripting/Natives/Generated/CMesh.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector3.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/Node.hpp>
#include <RED4ext/Scripting/Natives/Transform.hpp>

#include <cstdint>

namespace ExamineInteractionNative::World::Detail
{
enum class WorldMeshSelectionKind : uint8_t
{
    None = 0,
    Single = 1,
    InstancedDestructible = 2,
    Instanced = 3,
    Foliage = 4,
};

struct WorldMeshSelection
{
    RED4ext::worldINodeInstance* node{};
    WorldMeshSelectionKind kind{WorldMeshSelectionKind::None};
    int32_t index{-1};
    int32_t count{};
    RED4ext::ResourcePath path{};
    RED4ext::CName appearance{};
    RED4ext::Box localBounds{};
    RED4ext::Quaternion orientation{};
    RED4ext::Vector3 scale{1.0f, 1.0f, 1.0f};
};

struct WorldMeshNodeCache
{
    WorldMeshSelectionKind kind{WorldMeshSelectionKind::None};
    RED4ext::worldNode* definition{};
    RED4ext::ResourcePath path{};
    RED4ext::CName appearance{};
    RED4ext::Transform rootTransform{};
    RED4ext::Vector3 rootScale{};
    RED4ext::Box localBounds{};
    RED4ext::Box broadBounds[2]{};
    uint8_t broadBoundsCount{};
    bool rootDataValid{};
};

struct WorldEntityNodeCache
{
    RED4ext::Box worldBounds{};
};

struct WorldMeshProbeStats
{
    uint32_t singleNodes{};
    uint32_t instancedDestructibleNodes{};
    uint32_t instancedNodes{};
    uint32_t foliageNodes{};
    uint64_t singleBoundsTests{};
    uint64_t instancedDestructibleInstanceTests{};
    uint64_t instancedBoundsTests{};
    uint64_t foliageInstanceTests{};
    uint64_t cachedBroadPhaseTests{};
    uint64_t cachedBroadPhaseRejected{};
    uint32_t foliageNotVisible{};
    uint32_t foliageRootReadFailed{};
    uint32_t foliageBoundsUnavailable{};
    uint32_t foliagePopulationUnavailable{};
    uint32_t foliageNoIntersection{};
    uint32_t foliageSelected{};
    uint32_t destructibleHidden{};
    uint32_t destructibleBoundsUnavailable{};
    uint32_t destructibleTransformsUnavailable{};
    uint32_t destructibleSelected{};
};

RED4ext::worldNode* GetWorldNodeDefinition(RED4ext::worldINodeInstance* aNodeInstance);
WorldMeshSelectionKind GetWorldMeshSelectionKind(RED4ext::worldINodeInstance* aNodeInstance);
bool TryReadWorldMeshInstance(RED4ext::worldINodeInstance* aNodeInstance,
                              RED4ext::Transform* aTransform, RED4ext::Vector3* aScale,
                              uint16_t* aState, RED4ext::Handle<RED4ext::CMesh>** aMeshHandle);
bool TryReadWorldNodeOrientation(RED4ext::worldINodeInstance* aNodeInstance,
                                 RED4ext::Quaternion* aOrientation);
bool IsWorldNodeAttachedAndVisible(RED4ext::worldINodeInstance* aNodeInstance);
bool TryGetLoadedMeshBounds(RED4ext::ResourcePath aPath, RED4ext::Box& aBounds);
RED4ext::ResourcePath GetWorldMeshPath(RED4ext::worldINodeInstance* aNodeInstance);
RED4ext::CName GetWorldMeshAppearance(RED4ext::worldINodeInstance* aNodeInstance);
bool TryBuildWorldMeshNodeCache(RED4ext::worldINodeInstance* aNodeInstance,
                                WorldMeshNodeCache& aCache);
bool IntersectRayBox(const RED4ext::Vector4& aOrigin, const RED4ext::Vector4& aDirection,
                     const RED4ext::Box& aBounds, float aMaxDistance, float& aDistance);
bool TrySelectWorldMeshInstance(RED4ext::worldINodeInstance* aNodeInstance,
                                const RED4ext::Vector4& aOrigin,
                                const RED4ext::Vector4& aDirection,
                                float aMaxDistance, WorldMeshSelection& aSelection,
                                float& aDistance,
                                WorldMeshProbeStats* aProbeStats = nullptr,
                                const WorldMeshNodeCache* aCache = nullptr);
void ClearInstanceResources();
}

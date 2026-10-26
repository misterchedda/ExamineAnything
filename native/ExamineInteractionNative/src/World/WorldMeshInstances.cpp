#include "WorldMeshInternal.hpp"

#include <RED4ext/ResourceLoader.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/FoliageCompiledResource.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/FoliageNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/InstancedDestructibleMeshNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/InstancedMeshNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/WorldTransform.hpp>

#include <Windows.h>

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <mutex>
#include <unordered_map>

namespace ExamineInteractionNative::World::Detail
{
namespace
{
std::mutex g_foliageResourcesLock;
std::unordered_map<
    uint64_t,
    RED4ext::SharedPtr<RED4ext::ResourceToken<RED4ext::worldFoliageCompiledResource>>>
    g_foliageResources;

struct RenderProxyTransform
{
    RED4ext::WorldTransform transform;
    RED4ext::Vector3 scale;
};

static_assert(sizeof(RenderProxyTransform) == 0x30);
}

bool TryGetRenderProxyTransforms(
    RED4ext::worldInstancedMeshNode* aDefinition, RED4ext::worldINodeInstance* aInstance,
    const RenderProxyTransform*& aTransforms, int32_t& aCount)
{
    aTransforms = nullptr;
    aCount = 0;
    if (!aDefinition)
    {
        return false;
    }

    __try
    {
        auto* node = reinterpret_cast<const std::byte*>(aDefinition);
        const auto index = *reinterpret_cast<const uint32_t*>(
            reinterpret_cast<const std::byte*>(aInstance) + 0x88);
        // Engine span accessor at 2.5 RVA 0x20BF910.
        const auto& direct = *reinterpret_cast<const RED4ext::DynArray<RenderProxyTransform>*>(node + 0x60);
        if (direct.size() != 0)
        {
            aTransforms = direct.Data();
            aCount = static_cast<int32_t>(direct.size());
            return aTransforms && aCount > 0;
        }
        const auto rangeCount = *reinterpret_cast<const uint32_t*>(node + 0x8C);
        auto* ranges = *reinterpret_cast<const uint16_t* const*>(node + 0x80);
        if (!ranges || index >= rangeCount) return false;
        const auto begin = static_cast<uint32_t>(ranges[index * 2]);
        const auto count = static_cast<uint32_t>(ranges[index * 2 + 1]);
        const auto& raw = aDefinition->cookedWorldTransformsBuffer.buffer;
        const auto total = raw.size / sizeof(RenderProxyTransform);
        if (!raw.data || begin > total || count > total - begin || !count) return false;
        aTransforms = reinterpret_cast<const RenderProxyTransform*>(raw.data) + begin;
        aCount = static_cast<int32_t>(count);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        aTransforms = nullptr;
        aCount = 0;
        return false;
    }
}

bool TryGetCookedInstanceTransforms(
    RED4ext::worldInstancedDestructibleMeshNode* aDefinition,
    const RED4ext::Transform*& aTransforms, int32_t& aCount)
{
    aTransforms = nullptr;
    aCount = 0;
    if (!aDefinition)
    {
        return false;
    }

    __try
    {
        const auto& transforms = aDefinition->instanceTransforms;
        aTransforms = transforms.Data();
        aCount = static_cast<int32_t>(transforms.size());
        if (!aTransforms || aCount <= 0) return false;
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        aTransforms = nullptr;
        aCount = 0;
        return false;
    }
}

float DecodeHalfFloat(uint16_t aValue)
{
    const auto sign = (aValue & 0x8000u) != 0;
    const auto exponent = static_cast<uint32_t>((aValue >> 10u) & 0x1Fu);
    const auto mantissa = static_cast<uint32_t>(aValue & 0x03FFu);

    float value{};
    if (exponent == 0)
    {
        value = std::ldexp(static_cast<float>(mantissa), -24);
    }
    else if (exponent == 0x1Fu)
    {
        const uint32_t bits = 0x7F800000u | (mantissa << 13u);
        value = std::bit_cast<float>(bits);
    }
    else
    {
        value = std::ldexp(static_cast<float>(mantissa + 1024u),
                           static_cast<int32_t>(exponent) - 25);
    }
    return sign ? -value : value;
}

struct FoliagePopulationView
{
    const std::byte* positions{};
    const std::byte* scales{};
    const std::byte* rotations{};
    uint32_t start{};
    uint32_t count{};
};

bool TryReadFoliagePopulationView(RED4ext::worldFoliageCompiledResource* aResource,
                                  RED4ext::worldFoliageNode* aDefinition,
                                  FoliagePopulationView& aView)
{
    aView = {};
    if (!aResource || !aDefinition)
    {
        return false;
    }

    __try
    {
        const auto populationCount = static_cast<uint64_t>(aResource->populationCount);
        const auto bucketCount = static_cast<uint64_t>(aResource->bucketCount);
        const auto positionsSize = populationCount * sizeof(float) * 3u;
        const auto scalesSize = populationCount * sizeof(float);
        const auto rotationsSize = populationCount * sizeof(uint16_t) * 4u;
        const auto bucketsSize = bucketCount * sizeof(uint32_t) * 2u;
        const auto requiredSize = positionsSize + scalesSize + rotationsSize + bucketsSize;
        const auto& raw = aResource->dataBuffer.buffer;
        const auto start = static_cast<uint64_t>(aDefinition->populationSpanInfo.stancesBegin);
        const auto count = static_cast<uint64_t>(aDefinition->populationSpanInfo.stancesCount);

        if (!raw.data || requiredSize > raw.size || start > populationCount ||
            count > populationCount - start ||
            count > static_cast<uint64_t>(std::numeric_limits<uint32_t>::max()))
        {
            return false;
        }

        const auto* bytes = reinterpret_cast<const std::byte*>(raw.data);
        aView.positions = bytes;
        aView.scales = bytes + positionsSize;
        aView.rotations = bytes + positionsSize + scalesSize;
        aView.start = static_cast<uint32_t>(start);
        aView.count = static_cast<uint32_t>(count);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        aView = {};
        return false;
    }
}

bool TryGetFoliagePopulationView(RED4ext::worldFoliageNode* aDefinition,
                                 FoliagePopulationView& aView)
{
    aView = {};
    if (!aDefinition || aDefinition->foliageResource.path.IsEmpty())
    {
        return false;
    }

    auto* loader = RED4ext::ResourceLoader::Get();
    if (!loader)
    {
        return false;
    }

    auto token = loader->FindToken<RED4ext::worldFoliageCompiledResource>(
        aDefinition->foliageResource.path);
    if (!token)
    {
        std::scoped_lock lock(g_foliageResourcesLock);
        auto& cached = g_foliageResources[aDefinition->foliageResource.path.hash];
        if (!cached)
        {
            cached = loader->LoadAsync<RED4ext::worldFoliageCompiledResource>(
                aDefinition->foliageResource.path);
        }
        token = cached;
    }
    if (!token || !token->IsLoaded() || !token->Get())
    {
        return false;
    }

    return TryReadFoliagePopulationView(token->Get().GetPtr(), aDefinition, aView);
}

RED4ext::Transform ReadFoliageTransform(const FoliagePopulationView& aView,
                                        uint32_t aLocalIndex, float& aScale)
{
    const auto index = static_cast<uint64_t>(aView.start) + aLocalIndex;
    float position[3]{};
    uint16_t rotation[4]{};
    std::memcpy(position, aView.positions + index * sizeof(position), sizeof(position));
    std::memcpy(&aScale, aView.scales + index * sizeof(float), sizeof(float));
    std::memcpy(rotation, aView.rotations + index * sizeof(rotation), sizeof(rotation));

    RED4ext::Quaternion orientation{};
    orientation.i = DecodeHalfFloat(rotation[0]);
    orientation.j = DecodeHalfFloat(rotation[1]);
    orientation.k = DecodeHalfFloat(rotation[2]);
    orientation.r = DecodeHalfFloat(rotation[3]);
    orientation = orientation.Normalized();

    RED4ext::Vector4 worldPosition{};
    worldPosition.X = position[0];
    worldPosition.Y = position[1];
    worldPosition.Z = position[2];
    worldPosition.W = 0.0f;
    return {worldPosition, orientation};
}

namespace
{
void IncludeBounds(RED4ext::Box& aAggregate, bool& aHasAggregate,
                   const RED4ext::Box& aBounds)
{
    if (!aBounds.IsValid())
    {
        return;
    }

    if (!aHasAggregate)
    {
        aAggregate = aBounds;
        aHasAggregate = true;
        return;
    }

    aAggregate.Min.X = std::min(aAggregate.Min.X, aBounds.Min.X);
    aAggregate.Min.Y = std::min(aAggregate.Min.Y, aBounds.Min.Y);
    aAggregate.Min.Z = std::min(aAggregate.Min.Z, aBounds.Min.Z);
    aAggregate.Max.X = std::max(aAggregate.Max.X, aBounds.Max.X);
    aAggregate.Max.Y = std::max(aAggregate.Max.Y, aBounds.Max.Y);
    aAggregate.Max.Z = std::max(aAggregate.Max.Z, aBounds.Max.Z);
}

void AppendBroadBounds(WorldMeshNodeCache& aCache, const RED4ext::Box& aBounds)
{
    if (aBounds.IsValid() && aCache.broadBoundsCount < 2)
    {
        aCache.broadBounds[aCache.broadBoundsCount++] = aBounds;
    }
}
}

bool TryBuildWorldMeshNodeCache(RED4ext::worldINodeInstance* aNodeInstance,
                                WorldMeshNodeCache& aCache)
{
    aCache = {};
    if (!aNodeInstance)
    {
        return false;
    }

    aCache.kind = GetWorldMeshSelectionKind(aNodeInstance);
    aCache.definition = GetWorldNodeDefinition(aNodeInstance);
    if (aCache.kind == WorldMeshSelectionKind::None || !aCache.definition)
    {
        return false;
    }

    aCache.path = GetWorldMeshPath(aNodeInstance);
    aCache.appearance = GetWorldMeshAppearance(aNodeInstance);

    RED4ext::Handle<RED4ext::CMesh>* runtimeMesh{};
    uint16_t state{};
    if (aCache.kind == WorldMeshSelectionKind::Instanced)
    {
        __try
        {
            aCache.rootTransform = *reinterpret_cast<RED4ext::Transform*>(
                reinterpret_cast<std::byte*>(aNodeInstance) + 0x30);
            aCache.rootScale = *reinterpret_cast<RED4ext::Vector3*>(
                reinterpret_cast<std::byte*>(aNodeInstance) + 0x50);
            aCache.rootDataValid = true;
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            aCache.rootDataValid = false;
        }
    }
    else
    {
        aCache.rootDataValid = TryReadWorldMeshInstance(
            aNodeInstance, &aCache.rootTransform, &aCache.rootScale, &state, &runtimeMesh);
    }

    if (aCache.kind == WorldMeshSelectionKind::Foliage)
    {
        __try
        {
            runtimeMesh = reinterpret_cast<RED4ext::Handle<RED4ext::CMesh>*>(
                reinterpret_cast<std::byte*>(aNodeInstance) + 0xB8);
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            runtimeMesh = nullptr;
        }
    }

    if (runtimeMesh && *runtimeMesh)
    {
        aCache.localBounds = (*runtimeMesh)->boundingBox;
    }
    if (!aCache.localBounds.IsValid() && !aCache.path.IsEmpty())
    {
        TryGetLoadedMeshBounds(aCache.path, aCache.localBounds);
    }

    if (aCache.kind == WorldMeshSelectionKind::Single &&
        aCache.rootDataValid && aCache.localBounds.IsValid())
    {
        auto worldBounds = aCache.localBounds;
        worldBounds *= RED4ext::Vector4(aCache.rootScale.X, aCache.rootScale.Y,
                                        aCache.rootScale.Z, 0.0f);
        worldBounds *= aCache.rootTransform.orientation;
        worldBounds += aCache.rootTransform.position;
        AppendBroadBounds(aCache, worldBounds);
    }
    else if (aCache.kind == WorldMeshSelectionKind::Instanced)
    {
        auto* definition = reinterpret_cast<RED4ext::worldInstancedMeshNode*>(
            aCache.definition);
        const RenderProxyTransform* authoredTransforms{};
        int32_t authoredInstanceCount{};
        if (aCache.localBounds.IsValid() &&
            TryGetRenderProxyTransforms(definition, aNodeInstance, authoredTransforms,
                                        authoredInstanceCount))
        {
            RED4ext::Box aggregate{};
            bool hasAggregate = false;
            for (int32_t index = 0; index < authoredInstanceCount; ++index)
            {
                const auto& authored = authoredTransforms[index];
                auto worldBounds = aCache.localBounds;
                worldBounds *= RED4ext::Vector4(authored.scale.X, authored.scale.Y,
                                                authored.scale.Z, 0.0f);
                worldBounds *= authored.transform.Orientation;
                worldBounds += authored.transform.Position.AsVector4();
                IncludeBounds(aggregate, hasAggregate, worldBounds);
            }
            if (hasAggregate)
            {
                AppendBroadBounds(aCache, aggregate);
            }
        }
    }
    else if (aCache.kind == WorldMeshSelectionKind::InstancedDestructible &&
             aCache.rootDataValid && aCache.localBounds.IsValid())
    {
        auto* definition = reinterpret_cast<RED4ext::worldInstancedDestructibleMeshNode*>(
            aCache.definition);
        const RED4ext::Transform* cookedTransforms{};
        int32_t cookedInstanceCount{};
        if (TryGetCookedInstanceTransforms(definition, cookedTransforms, cookedInstanceCount))
        {
            RED4ext::Box aggregate{};
            bool hasAggregate = false;
            for (int32_t index = 0; index < cookedInstanceCount; ++index)
            {
                auto instanceTransform = cookedTransforms[index];
                instanceTransform.position.X *= aCache.rootScale.X;
                instanceTransform.position.Y *= aCache.rootScale.Y;
                instanceTransform.position.Z *= aCache.rootScale.Z;
                const auto worldTransform = instanceTransform * aCache.rootTransform;

                auto worldBounds = aCache.localBounds;
                worldBounds *= RED4ext::Vector4(aCache.rootScale.X, aCache.rootScale.Y,
                                                aCache.rootScale.Z, 0.0f);
                worldBounds *= worldTransform.orientation;
                worldBounds += worldTransform.position;
                IncludeBounds(aggregate, hasAggregate, worldBounds);
            }
            if (hasAggregate)
            {
                AppendBroadBounds(aCache, aggregate);
            }
        }
    }
    else if (aCache.kind == WorldMeshSelectionKind::Foliage)
    {
        auto* definition = reinterpret_cast<RED4ext::worldFoliageNode*>(aCache.definition);
        if (definition->foliageLocalBounds.IsValid())
        {
            // Some cooked foliage bounds are already world-space while others are root-relative. Preserve both interpretations as separate broad-phase candidates rather than unioning them into a huge box.
            AppendBroadBounds(aCache, definition->foliageLocalBounds);
            if (aCache.rootDataValid)
            {
                auto rootedBounds = definition->foliageLocalBounds;
                rootedBounds *= RED4ext::Vector4(aCache.rootScale.X, aCache.rootScale.Y,
                                                 aCache.rootScale.Z, 0.0f);
                rootedBounds *= aCache.rootTransform.orientation;
                rootedBounds += aCache.rootTransform.position;
                AppendBroadBounds(aCache, rootedBounds);
            }
        }
    }

    return true;
}

bool TrySelectWorldMeshInstance(RED4ext::worldINodeInstance* aNodeInstance,
                                const RED4ext::Vector4& aOrigin,
                                const RED4ext::Vector4& aDirection,
                                float aMaxDistance,
                                WorldMeshSelection& aSelection,
                                float& aDistance,
                                WorldMeshProbeStats* aProbeStats,
                                const WorldMeshNodeCache* aCache)
{
    if (!aNodeInstance)
    {
        return false;
    }

    const auto kind = aCache ? aCache->kind : GetWorldMeshSelectionKind(aNodeInstance);
    if (aProbeStats)
    {
        switch (kind)
        {
        case WorldMeshSelectionKind::Single:
            ++aProbeStats->singleNodes;
            break;
        case WorldMeshSelectionKind::InstancedDestructible:
            ++aProbeStats->instancedDestructibleNodes;
            break;
        case WorldMeshSelectionKind::Instanced:
            ++aProbeStats->instancedNodes;
            break;
        case WorldMeshSelectionKind::Foliage:
            ++aProbeStats->foliageNodes;
            break;
        default:
            break;
        }
    }
    if (!IsWorldNodeAttachedAndVisible(aNodeInstance))
    {
        if (kind == WorldMeshSelectionKind::InstancedDestructible && aProbeStats)
            ++aProbeStats->destructibleHidden;
        if (kind == WorldMeshSelectionKind::Foliage && aProbeStats)
        {
            ++aProbeStats->foliageNotVisible;
        }
        return false;
    }

    const auto path = aCache ? aCache->path : GetWorldMeshPath(aNodeInstance);
    auto* nodeDefinition = aCache ? aCache->definition : GetWorldNodeDefinition(aNodeInstance);
    if (kind == WorldMeshSelectionKind::None || path.IsEmpty() || !nodeDefinition)
    {
        return false;
    }

    bool cachedBroadHit = false;
    float cachedBroadDistance = std::numeric_limits<float>::max();
    if (aCache && aCache->broadBoundsCount != 0)
    {
        for (uint8_t index = 0; index < aCache->broadBoundsCount; ++index)
        {
            if (aProbeStats)
            {
                ++aProbeStats->cachedBroadPhaseTests;
            }
            float distance{};
            if (IntersectRayBox(aOrigin, aDirection, aCache->broadBounds[index],
                                aMaxDistance, distance))
            {
                cachedBroadHit = true;
                cachedBroadDistance = std::min(cachedBroadDistance, distance);
            }
        }
        if (!cachedBroadHit)
        {
            if (aProbeStats)
            {
                ++aProbeStats->cachedBroadPhaseRejected;
                if (kind == WorldMeshSelectionKind::Foliage)
                {
                    ++aProbeStats->foliageNoIntersection;
                }
            }
            return false;
        }
    }

    RED4ext::Transform rootTransform{};
    RED4ext::Vector3 rootScale{};
    RED4ext::Handle<RED4ext::CMesh>* runtimeMesh{};
    uint16_t state{};
    if (aCache && aCache->rootDataValid)
    {
        rootTransform = aCache->rootTransform;
        rootScale = aCache->rootScale;
    }
    else if (kind != WorldMeshSelectionKind::Instanced &&
             !TryReadWorldMeshInstance(aNodeInstance, &rootTransform, &rootScale,
                                       &state, &runtimeMesh))
    {
        if (kind == WorldMeshSelectionKind::Foliage && aProbeStats)
        {
            ++aProbeStats->foliageRootReadFailed;
        }
        return false;
    }

    if (kind == WorldMeshSelectionKind::Instanced &&
        (!aCache || !aCache->rootDataValid))
    {
        __try
        {
            rootTransform = *reinterpret_cast<RED4ext::Transform*>(
                reinterpret_cast<std::byte*>(aNodeInstance) + 0x30);
            rootScale = *reinterpret_cast<RED4ext::Vector3*>(
                reinterpret_cast<std::byte*>(aNodeInstance) + 0x50);
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            return false;
        }
    }
    else if (kind == WorldMeshSelectionKind::Foliage)
    {
        // Foliage instances keep the loaded CMesh handle later in their runtime layout than ordinary worldMeshNodeInstance objects.
        __try
        {
            runtimeMesh = reinterpret_cast<RED4ext::Handle<RED4ext::CMesh>*>(
                reinterpret_cast<std::byte*>(aNodeInstance) + 0xB8);
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            runtimeMesh = nullptr;
        }
    }

    RED4ext::Box localBounds = aCache ? aCache->localBounds : RED4ext::Box{};
    if (runtimeMesh && *runtimeMesh)
    {
        localBounds = (*runtimeMesh)->boundingBox;
    }
    if (!localBounds.IsValid())
    {
        TryGetLoadedMeshBounds(path, localBounds);
    }

    if (kind == WorldMeshSelectionKind::InstancedDestructible &&
        !localBounds.IsValid() && aProbeStats)
        ++aProbeStats->destructibleBoundsUnavailable;

    float nearestDistance = std::numeric_limits<float>::max();
    int32_t nearestIndex = -1;
    RED4ext::Box nearestWorldBounds{};
    RED4ext::Quaternion nearestOrientation = rootTransform.orientation;
    RED4ext::Vector3 nearestScale = rootScale;
    int32_t cookedInstanceCount = 0;
    int32_t authoredInstanceCount = 0;

    if (kind == WorldMeshSelectionKind::Single && cachedBroadHit &&
        localBounds.IsValid())
    {
        if (aProbeStats)
        {
            ++aProbeStats->singleBoundsTests;
        }
        nearestDistance = cachedBroadDistance;
        nearestIndex = 0;
        nearestWorldBounds = aCache->broadBounds[0];
    }
    else if (kind == WorldMeshSelectionKind::InstancedDestructible && localBounds.IsValid())
    {
        auto* definition = reinterpret_cast<RED4ext::worldInstancedDestructibleMeshNode*>(
            nodeDefinition);
        const RED4ext::Transform* cookedTransforms{};
        if (!TryGetCookedInstanceTransforms(definition, cookedTransforms, cookedInstanceCount))
        {
            if (aProbeStats) ++aProbeStats->destructibleTransformsUnavailable;
            return false;
        }

        for (int32_t index = 0; index < cookedInstanceCount; ++index)
        {
            if (aProbeStats)
            {
                ++aProbeStats->instancedDestructibleInstanceTests;
            }
            auto instanceTransform = cookedTransforms[index];
            instanceTransform.position.X *= rootScale.X;
            instanceTransform.position.Y *= rootScale.Y;
            instanceTransform.position.Z *= rootScale.Z;
            const auto worldTransform = instanceTransform * rootTransform;

            auto worldBounds = localBounds;
            worldBounds *= RED4ext::Vector4(rootScale.X, rootScale.Y, rootScale.Z, 0.0f);
            worldBounds *= worldTransform.orientation;
            worldBounds += worldTransform.position;

            float distance{};
            if (worldBounds.IsValid() &&
                IntersectRayBox(aOrigin, aDirection, worldBounds, aMaxDistance, distance) &&
                distance < nearestDistance)
            {
                nearestDistance = distance;
                nearestIndex = index;
                nearestWorldBounds = worldBounds;
                nearestOrientation = worldTransform.orientation;
                nearestScale = rootScale;
            }
        }
    }
    else if (kind == WorldMeshSelectionKind::Foliage && localBounds.IsValid())
    {
        auto* definition = reinterpret_cast<RED4ext::worldFoliageNode*>(nodeDefinition);

        // The foliage renderer does not retain its population resource in the ordinary ResourceLoader token table. Use the node's aggregate bounds as a cheap broad phase, then lazily load only a resource whose slice is actually under this camera ray.
        if ((!aCache || aCache->broadBoundsCount == 0) &&
            definition->foliageLocalBounds.IsValid())
        {
            bool coarseHit = false;
            const auto testCoarseBounds = [&](const RED4ext::Box& aBounds) {
                float distance{};
                if (aBounds.IsValid() &&
                    IntersectRayBox(aOrigin, aDirection, aBounds, aMaxDistance, distance))
                {
                    coarseHit = true;
                }
            };

            testCoarseBounds(definition->foliageLocalBounds);

            auto rootedBounds = definition->foliageLocalBounds;
            rootedBounds *= RED4ext::Vector4(rootScale.X, rootScale.Y, rootScale.Z, 0.0f);
            rootedBounds *= rootTransform.orientation;
            rootedBounds += rootTransform.position;
            testCoarseBounds(rootedBounds);

            if (!coarseHit)
            {
                if (aProbeStats)
                {
                    ++aProbeStats->foliageNoIntersection;
                }
                return false;
            }
        }

        FoliagePopulationView population{};
        if (!TryGetFoliagePopulationView(definition, population))
        {
            if (aProbeStats)
            {
                ++aProbeStats->foliagePopulationUnavailable;
            }
            return false;
        }

        for (uint32_t index = 0; index < population.count; ++index)
        {
            if (aProbeStats)
            {
                ++aProbeStats->foliageInstanceTests;
            }
            float instanceScale = 1.0f;
            const auto authoredTransform = ReadFoliageTransform(population, index, instanceScale);
            const RED4ext::Vector4 instanceScaleVector(
                rootScale.X * instanceScale,
                rootScale.Y * instanceScale,
                rootScale.Z * instanceScale,
                0.0f);

            const auto testTransform = [&](const RED4ext::Transform& aWorldTransform) {
                auto worldBounds = localBounds;
                worldBounds *= instanceScaleVector;
                worldBounds *= aWorldTransform.orientation;
                worldBounds += aWorldTransform.position;

                float distance{};
                if (worldBounds.IsValid() &&
                    IntersectRayBox(aOrigin, aDirection, worldBounds, aMaxDistance, distance) &&
                    distance < nearestDistance)
                {
                    nearestDistance = distance;
                    nearestIndex = static_cast<int32_t>(index);
                    nearestWorldBounds = worldBounds;
                    nearestOrientation = aWorldTransform.orientation;
                    nearestScale = {instanceScaleVector.X, instanceScaleVector.Y,
                                    instanceScaleVector.Z};
                }
            };

            // Generated foliage resources normally store world-space population transforms. Retain the root-relative interpretation as a compatibility fallback for differently cooked resources; only a transform whose AABB intersects the camera ray can win.
            testTransform(authoredTransform);

            auto relativeTransform = authoredTransform;
            relativeTransform.position.X *= rootScale.X;
            relativeTransform.position.Y *= rootScale.Y;
            relativeTransform.position.Z *= rootScale.Z;
            testTransform(relativeTransform * rootTransform);
        }
    }
    else if (kind == WorldMeshSelectionKind::Instanced)
    {
        auto* definition = reinterpret_cast<RED4ext::worldInstancedMeshNode*>(
            nodeDefinition);
        const RenderProxyTransform* authoredTransforms{};
        if (!localBounds.IsValid() ||
            !TryGetRenderProxyTransforms(definition, aNodeInstance, authoredTransforms,
                                         authoredInstanceCount))
        {
            return false;
        }

        for (int32_t index = 0; index < authoredInstanceCount; ++index)
        {
            if (aProbeStats)
            {
                ++aProbeStats->instancedBoundsTests;
            }

            const auto& authored = authoredTransforms[index];
            auto worldBounds = localBounds;
            worldBounds *= RED4ext::Vector4(authored.scale.X, authored.scale.Y,
                                            authored.scale.Z, 0.0f);
            worldBounds *= authored.transform.Orientation;
            worldBounds += authored.transform.Position.AsVector4();

            float distance{};
            if (worldBounds.IsValid() &&
                IntersectRayBox(aOrigin, aDirection, worldBounds, aMaxDistance, distance) &&
                distance < nearestDistance)
            {
                nearestDistance = distance;
                nearestIndex = index;
                nearestWorldBounds = worldBounds;
                nearestOrientation = authored.transform.Orientation;
                nearestScale = authored.scale;
            }
        }
    }
    else if (localBounds.IsValid())
    {
        if (aProbeStats)
        {
            ++aProbeStats->singleBoundsTests;
        }
        auto worldBounds = localBounds;
        worldBounds *= RED4ext::Vector4(rootScale.X, rootScale.Y, rootScale.Z, 0.0f);
        worldBounds *= rootTransform.orientation;
        worldBounds += rootTransform.position;

        float distance{};
        if (worldBounds.IsValid() &&
            IntersectRayBox(aOrigin, aDirection, worldBounds, aMaxDistance, distance))
        {
            nearestDistance = distance;
            nearestIndex = 0;
            nearestWorldBounds = worldBounds;
        }
    }

    if (nearestIndex < 0 || !localBounds.IsValid())
    {
        if (kind == WorldMeshSelectionKind::Foliage && aProbeStats)
        {
            if (!localBounds.IsValid())
            {
                ++aProbeStats->foliageBoundsUnavailable;
            }
            else
            {
                ++aProbeStats->foliageNoIntersection;
            }
        }
        return false;
    }

    int32_t selectionCount = 1;
    if (kind == WorldMeshSelectionKind::InstancedDestructible)
    {
        selectionCount = cookedInstanceCount;
    }
    else if (kind == WorldMeshSelectionKind::Instanced)
    {
        selectionCount = authoredInstanceCount;
    }
    else if (kind == WorldMeshSelectionKind::Foliage)
    {
        selectionCount = static_cast<int32_t>(
            reinterpret_cast<RED4ext::worldFoliageNode*>(nodeDefinition)
                ->populationSpanInfo.stancesCount);
    }

    if (kind == WorldMeshSelectionKind::InstancedDestructible && aProbeStats)
        ++aProbeStats->destructibleSelected;
    aSelection.node = aNodeInstance;
    aSelection.kind = kind;
    aSelection.index = nearestIndex;
    aSelection.count = selectionCount;
    aSelection.path = path;
    aSelection.appearance = aCache ? aCache->appearance : GetWorldMeshAppearance(aNodeInstance);
    aSelection.localBounds = localBounds;
    aSelection.orientation = nearestOrientation;
    aSelection.scale = nearestScale;
    aDistance = nearestDistance;
    if (kind == WorldMeshSelectionKind::Foliage && aProbeStats)
    {
        ++aProbeStats->foliageSelected;
    }
    return true;
}

void ClearInstanceResources()
{
    std::scoped_lock lock(g_foliageResourcesLock);
    g_foliageResources.clear();
}
} // namespace ExamineInteractionNative::World::Detail

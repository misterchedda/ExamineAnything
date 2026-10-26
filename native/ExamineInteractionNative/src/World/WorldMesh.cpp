#include "WorldMesh.hpp"
#include "WorldMeshInternal.hpp"
#include "../Engine/Addresses.hpp"
#include "../Engine/Logging.hpp"

#include <RED4ext/Relocation.hpp>
#include <RED4ext/ResourceLoader.hpp>
#include <RED4ext/Scripting/Natives/Generated/CMesh.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector3.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/Entity.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/EntityNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/EntityNodeInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/AdvertisementNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/FoliageCompiledResource.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/FoliageNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/InstancedDestructibleMeshNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/InstancedMeshNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/MeshNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/CookedMeshNode.hpp>
#include <RED4ext/Scripting/Natives/Transform.hpp>

#include <Windows.h>

#include <algorithm>
#include <atomic>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <mutex>
#include <shared_mutex>
#include <unordered_map>
#include <vector>

namespace ExamineInteractionNative::World
{
namespace Detail
{
using WorldNodeInstanceAttach_t = void (*)(RED4ext::worldINodeInstance*, void*);
WorldNodeInstanceAttach_t g_worldNodeInstanceAttachOriginal{};
WorldNodeInstanceAttach_t g_worldNodeInstanceDetachOriginal{};
void* g_worldNodeInstanceAttachAddress{};
void* g_worldNodeInstanceDetachAddress{};
std::shared_mutex g_worldMeshNodesLock;
// Attach/detach hooks define the lifetime of these instances. Keeping only raw pointers avoids promoting every streamed node's weak handle on every aim query (tens of thousands of ref-count operations per poll).
std::unordered_map<RED4ext::worldINodeInstance*, WorldMeshNodeCache> g_worldMeshNodes;
std::unordered_map<RED4ext::worldINodeInstance*, WorldEntityNodeCache> g_worldEntityNodes;
std::atomic<uint64_t> g_worldMeshNodesVersion{};
std::atomic<RED4ext::worldINodeInstance*> g_lastWorldMeshCandidate{};

std::mutex g_worldMeshSelectionLock;
WorldMeshSelection g_worldMeshSelection;

// Independent channels keep common static meshes from exhausting rare-node diagnostics.
std::atomic<uint64_t> g_meshCacheFailures[5]{};
std::atomic<uint64_t> g_entityCacheFailures{};
bool DiagnosticDue(std::atomic<uint64_t>& aNext, uint64_t aIntervalMs)
{
    if (!Logging::DiagnosticsEnabled()) return false;
    const auto now = GetTickCount64();
    auto next = aNext.load(std::memory_order_relaxed);
    return now >= next && aNext.compare_exchange_strong(next, now + aIntervalMs,
                                                       std::memory_order_relaxed);
}

void LogMeshDiagnostic(const char* aStage, const WorldMeshSelection& aSelection)
{
    auto* definition = GetWorldNodeDefinition(aSelection.node);
    uint32_t cookedIndex = UINT32_MAX;
    uint32_t stride = 0;
    uint32_t bytes = 0;
    __try
    {
        cookedIndex = *reinterpret_cast<uint32_t*>(
            reinterpret_cast<std::byte*>(aSelection.node) + 0x88);
        if (definition && aSelection.kind == WorldMeshSelectionKind::Single && cookedIndex != UINT32_MAX)
        {
            stride = *reinterpret_cast<uint32_t*>(reinterpret_cast<std::byte*>(definition) + 0x50);
            bytes = *reinterpret_cast<uint32_t*>(reinterpret_cast<std::byte*>(definition) + 0x4C);
        }
    }
    __except (EXCEPTION_EXECUTE_HANDLER) {}
    Logging::Diagnostic("2.5 mesh %s: type=%s kind=%u node=%p cookedIndex=%u stride=%u bytes=%u instance=%d/%d path=%llu appearance=%llu bounds=%u.",
                  aStage, definition ? definition->GetType()->GetName().ToString() : "unknown",
                  static_cast<uint32_t>(aSelection.kind), aSelection.node, cookedIndex, stride, bytes,
                  aSelection.index, aSelection.count, aSelection.path.hash, aSelection.appearance.hash,
                  aSelection.localBounds.IsValid() ? 1u : 0u);
}

struct WorldMeshRayHit
{
    WorldMeshSelection selection;
    float distance{};
};

struct WorldMeshRayCache
{
    bool valid{};
    RED4ext::Vector4 origin{};
    RED4ext::Vector4 direction{};
    float maxDistance{};
    uint64_t nodesVersion{};
    std::vector<WorldMeshRayHit> hits;
};

std::mutex g_worldMeshRayCacheLock;
WorldMeshRayCache g_worldMeshRayCache;

#if EXAMINE_INTERACTION_PROFILE_NATIVE
using ProfileClock = std::chrono::steady_clock;

struct NativeQueryProfileSample
{
    bool cacheHit{};
    bool selected{};
    uint64_t tracked{};
    uint64_t tested{};
    uint64_t hits{};
    uint64_t totalNs{};
    uint64_t cacheWaitNs{};
    uint64_t nodesWaitNs{};
    uint64_t scanNs{};
    uint64_t sortNs{};
    WorldMeshProbeStats workload{};
};

struct NativeQueryProfileAggregate
{
    ProfileClock::time_point lastLog{ProfileClock::now()};
    uint64_t queries{};
    uint64_t cacheHits{};
    uint64_t rebuilds{};
    uint64_t selected{};
    uint64_t tracked{};
    uint64_t tested{};
    uint64_t hits{};
    uint64_t totalNs{};
    uint64_t cacheWaitNs{};
    uint64_t nodesWaitNs{};
    uint64_t scanNs{};
    uint64_t sortNs{};
    uint64_t maxTotalNs{};
    uint64_t maxScanNs{};
    WorldMeshProbeStats workload{};
};

std::mutex g_nativeQueryProfileLock;
NativeQueryProfileAggregate g_nativeQueryProfile;

void AddProbeStats(WorldMeshProbeStats& aTarget, const WorldMeshProbeStats& aSource)
{
    aTarget.singleNodes += aSource.singleNodes;
    aTarget.instancedDestructibleNodes += aSource.instancedDestructibleNodes;
    aTarget.instancedNodes += aSource.instancedNodes;
    aTarget.foliageNodes += aSource.foliageNodes;
    aTarget.singleBoundsTests += aSource.singleBoundsTests;
    aTarget.instancedDestructibleInstanceTests += aSource.instancedDestructibleInstanceTests;
    aTarget.instancedBoundsTests += aSource.instancedBoundsTests;
    aTarget.foliageInstanceTests += aSource.foliageInstanceTests;
    aTarget.cachedBroadPhaseTests += aSource.cachedBroadPhaseTests;
    aTarget.cachedBroadPhaseRejected += aSource.cachedBroadPhaseRejected;
    aTarget.foliageNotVisible += aSource.foliageNotVisible;
    aTarget.foliageRootReadFailed += aSource.foliageRootReadFailed;
    aTarget.foliageBoundsUnavailable += aSource.foliageBoundsUnavailable;
    aTarget.foliagePopulationUnavailable += aSource.foliagePopulationUnavailable;
    aTarget.foliageNoIntersection += aSource.foliageNoIntersection;
    aTarget.foliageSelected += aSource.foliageSelected;
}

void RecordNativeQueryProfile(const NativeQueryProfileSample& aSample)
{
    std::scoped_lock lock(g_nativeQueryProfileLock);
    auto& profile = g_nativeQueryProfile;
    ++profile.queries;
    profile.cacheHits += aSample.cacheHit ? 1u : 0u;
    profile.rebuilds += aSample.cacheHit ? 0u : 1u;
    profile.selected += aSample.selected ? 1u : 0u;
    profile.totalNs += aSample.totalNs;
    profile.cacheWaitNs += aSample.cacheWaitNs;
    profile.nodesWaitNs += aSample.nodesWaitNs;
    profile.maxTotalNs = std::max(profile.maxTotalNs, aSample.totalNs);
    if (!aSample.cacheHit)
    {
        profile.tracked += aSample.tracked;
        profile.tested += aSample.tested;
        profile.hits += aSample.hits;
        profile.scanNs += aSample.scanNs;
        profile.sortNs += aSample.sortNs;
        profile.maxScanNs = std::max(profile.maxScanNs, aSample.scanNs);
        AddProbeStats(profile.workload, aSample.workload);
    }

    const auto now = ProfileClock::now();
    if (now - profile.lastLog < std::chrono::seconds(5))
    {
        return;
    }

    const auto queries = std::max<uint64_t>(profile.queries, 1u);
    const auto rebuilds = std::max<uint64_t>(profile.rebuilds, 1u);
    const auto toAverageUs = [](uint64_t aNanoseconds, uint64_t aCount) {
        return static_cast<double>(aNanoseconds) / static_cast<double>(aCount) / 1000.0;
    };
    const auto toAverage = [](uint64_t aValue, uint64_t aCount) {
        return static_cast<double>(aValue) / static_cast<double>(aCount);
    };

    Logging::Diagnostic(
        "PROFILE world query: queries=%llu cacheHits=%llu rebuilds=%llu selected=%llu "
        "avgUs(total=%.2f cacheWait=%.2f nodeWait=%.2f scan=%.2f sort=%.2f) "
        "maxUs(total=%.2f scan=%.2f) avgRebuildNodes(tracked=%.1f tested=%.1f hits=%.1f).",
        static_cast<unsigned long long>(profile.queries),
        static_cast<unsigned long long>(profile.cacheHits),
        static_cast<unsigned long long>(profile.rebuilds),
        static_cast<unsigned long long>(profile.selected),
        toAverageUs(profile.totalNs, queries),
        toAverageUs(profile.cacheWaitNs, queries),
        toAverageUs(profile.nodesWaitNs, queries),
        toAverageUs(profile.scanNs, rebuilds),
        toAverageUs(profile.sortNs, rebuilds),
        static_cast<double>(profile.maxTotalNs) / 1000.0,
        static_cast<double>(profile.maxScanNs) / 1000.0,
        toAverage(profile.tracked, rebuilds),
        toAverage(profile.tested, rebuilds),
        toAverage(profile.hits, rebuilds));
    Logging::Diagnostic(
        "PROFILE world workload/rebuild: nodes(single=%.1f destructible=%.1f instanced=%.1f foliage=%.1f) "
        "boundsTests(single=%.1f destructible=%.1f instanced=%.1f foliage=%.1f) "
        "cachedBroad(tests=%.1f rejected=%.1f) foliage(miss=%u selected=%u unavailable=%u).",
        toAverage(profile.workload.singleNodes, rebuilds),
        toAverage(profile.workload.instancedDestructibleNodes, rebuilds),
        toAverage(profile.workload.instancedNodes, rebuilds),
        toAverage(profile.workload.foliageNodes, rebuilds),
        toAverage(profile.workload.singleBoundsTests, rebuilds),
        toAverage(profile.workload.instancedDestructibleInstanceTests, rebuilds),
        toAverage(profile.workload.instancedBoundsTests, rebuilds),
        toAverage(profile.workload.foliageInstanceTests, rebuilds),
        toAverage(profile.workload.cachedBroadPhaseTests, rebuilds),
        toAverage(profile.workload.cachedBroadPhaseRejected, rebuilds),
        profile.workload.foliageNoIntersection,
        profile.workload.foliageSelected,
        profile.workload.foliagePopulationUnavailable);

    profile = {};
    profile.lastLog = now;
}
#endif

struct RenderProxy
{
    virtual ~RenderProxy() = 0;
};

template<typename T>
RED4ext::WeakHandle<T> ToWeakHandle(T* aInstance)
{
    if (!aInstance)
    {
        return {};
    }

    return *reinterpret_cast<RED4ext::WeakHandle<T>*>(&aInstance->ref);
}

RED4ext::worldNode* GetWorldNodeDefinition(RED4ext::worldINodeInstance* aNodeInstance)
{
    if (!aNodeInstance)
    {
        return nullptr;
    }

    RED4ext::Handle<RED4ext::worldNode>* nodeDefinition{};
    __try
    {
        nodeDefinition = reinterpret_cast<RED4ext::Handle<RED4ext::worldNode>*>(
            reinterpret_cast<std::byte*>(aNodeInstance) + Addresses::WorldNodeDefinitionOffset);
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return nullptr;
    }

    return nodeDefinition && *nodeDefinition ? nodeDefinition->GetPtr() : nullptr;
}

WorldMeshSelectionKind GetWorldMeshSelectionKind(RED4ext::worldINodeInstance* aNodeInstance)
{
    auto* nodeDefinition = GetWorldNodeDefinition(aNodeInstance);
    if (!nodeDefinition)
    {
        return WorldMeshSelectionKind::None;
    }

    auto* rtti = RED4ext::CRTTISystem::Get();
    auto* instancedDestructibleType = rtti ? rtti->GetClass(
        RED4ext::worldInstancedDestructibleMeshNode::NAME) : nullptr;
    auto* instancedType = rtti ? rtti->GetClass(RED4ext::worldInstancedMeshNode::NAME) : nullptr;
    auto* foliageType = rtti ? rtti->GetClass(RED4ext::worldFoliageNode::NAME) : nullptr;
    auto* meshNodeType = rtti ? rtti->GetClass(RED4ext::worldMeshNode::NAME) : nullptr;

    if (instancedDestructibleType && nodeDefinition->GetType()->IsA(instancedDestructibleType))
    {
        return WorldMeshSelectionKind::InstancedDestructible;
    }
    if (instancedType && nodeDefinition->GetType()->IsA(instancedType))
    {
        return WorldMeshSelectionKind::Instanced;
    }
    if (foliageType && nodeDefinition->GetType()->IsA(foliageType))
    {
        return WorldMeshSelectionKind::Foliage;
    }
    auto* cookedMeshType = rtti ? rtti->GetClass(RED4ext::world::CookedMeshNode::NAME) : nullptr;
    if ((meshNodeType && nodeDefinition->GetType()->IsA(meshNodeType)) ||
        (cookedMeshType && nodeDefinition->GetType()->IsA(cookedMeshType)))
    {
        return WorldMeshSelectionKind::Single;
    }
    return WorldMeshSelectionKind::None;
}

bool IsMeshNodeInstance(RED4ext::worldINodeInstance* aNodeInstance)
{
    return GetWorldMeshSelectionKind(aNodeInstance) != WorldMeshSelectionKind::None;
}

RED4ext::worldAdvertisementNode* GetAdvertisementDefinition(
    RED4ext::worldINodeInstance* aNodeInstance)
{
    auto* nodeDefinition = GetWorldNodeDefinition(aNodeInstance);
    auto* rtti = RED4ext::CRTTISystem::Get();
    auto* advertisementType = rtti ? rtti->GetClass(RED4ext::worldAdvertisementNode::NAME) : nullptr;
    return nodeDefinition && advertisementType && nodeDefinition->GetType()->IsA(advertisementType)
        ? static_cast<RED4ext::worldAdvertisementNode*>(nodeDefinition)
        : nullptr;
}

bool IsEntityNodeInstance(RED4ext::worldINodeInstance* aNodeInstance)
{
    auto* nodeDefinition = GetWorldNodeDefinition(aNodeInstance);
    auto* rtti = RED4ext::CRTTISystem::Get();
    auto* entityNodeType = rtti ? rtti->GetClass(RED4ext::worldEntityNode::NAME) : nullptr;
    return nodeDefinition && entityNodeType && nodeDefinition->GetType()->IsA(entityNodeType);
}

RED4ext::entEntity* GetWorldEntity(RED4ext::worldINodeInstance* aNodeInstance)
{
    if (!aNodeInstance || !IsEntityNodeInstance(aNodeInstance))
    {
        return nullptr;
    }

    __try
    {
        auto* entity = reinterpret_cast<RED4ext::Handle<RED4ext::entEntity>*>(
            reinterpret_cast<std::byte*>(aNodeInstance) + 0xA0);
        return entity && *entity ? entity->GetPtr() : nullptr;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return nullptr;
    }
}

bool TryBuildWorldEntityNodeCache(RED4ext::worldINodeInstance* aNodeInstance,
                                  WorldEntityNodeCache& aCache)
{
    auto* nodeDefinition = GetWorldNodeDefinition(aNodeInstance);
    if (!nodeDefinition || !IsEntityNodeInstance(aNodeInstance))
    {
        return false;
    }

    RED4ext::Box localBounds{{1.0f, 0.0f, 0.0f, 0.0f},
                             {-1.0f, 0.0f, 0.0f, 0.0f}};
    RED4ext::Transform transform{};
    RED4ext::Vector3 scale{};
    __try
    {
        using GetBoundingBox_t = void (*)(RED4ext::worldNode*, RED4ext::Box&);
        auto** vtable = *reinterpret_cast<void***>(nodeDefinition);
        auto getBoundingBox = reinterpret_cast<GetBoundingBox_t>(vtable[0x108 / sizeof(void*)]);
        if (!getBoundingBox)
        {
            return false;
        }
        getBoundingBox(nodeDefinition, localBounds);
        transform = *reinterpret_cast<RED4ext::Transform*>(
            reinterpret_cast<std::byte*>(aNodeInstance) + 0x30);
        scale = *reinterpret_cast<RED4ext::Vector3*>(
            reinterpret_cast<std::byte*>(aNodeInstance) + 0x50);
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }

    if (localBounds.Max.X < localBounds.Min.X ||
        localBounds.Max.Y < localBounds.Min.Y ||
        localBounds.Max.Z < localBounds.Min.Z)
    {
        return false;
    }

    localBounds *= RED4ext::Vector4(scale.X, scale.Y, scale.Z, 0.0f);
    localBounds *= transform.orientation;
    localBounds += transform.position;
    aCache.worldBounds = localBounds;
    return true;
}

void ClearWorldMeshSelection(RED4ext::worldINodeInstance* aExpected = nullptr)
{
    std::scoped_lock lock(g_worldMeshSelectionLock);
    if (!aExpected || g_worldMeshSelection.node == aExpected)
    {
        g_worldMeshSelection = {};
        g_lastWorldMeshCandidate.store(nullptr, std::memory_order_release);
    }
}

void StoreWorldMeshSelection(const WorldMeshSelection& aSelection)
{
    std::scoped_lock lock(g_worldMeshSelectionLock);
    if (g_worldMeshSelection.node != aSelection.node ||
        g_worldMeshSelection.index != aSelection.index)
    {
        static std::atomic<uint64_t> nextLog[5]{};
        if (DiagnosticDue(nextLog[static_cast<uint8_t>(aSelection.kind)], 2000))
            LogMeshDiagnostic("candidate", aSelection);
    }
    g_worldMeshSelection = aSelection;
    g_lastWorldMeshCandidate.store(aSelection.node, std::memory_order_release);
}

bool ReadWorldMeshSelection(RED4ext::worldINodeInstance* aNodeInstance,
                            WorldMeshSelection& aSelection)
{
    std::scoped_lock lock(g_worldMeshSelectionLock);
    if (!aNodeInstance || g_worldMeshSelection.node != aNodeInstance)
    {
        return false;
    }
    aSelection = g_worldMeshSelection;
    return true;
}

void TrackWorldMeshNode(RED4ext::worldINodeInstance* aNodeInstance)
{
    WorldMeshNodeCache cache{};
    WorldEntityNodeCache entityCache{};
    const bool isMesh = TryBuildWorldMeshNodeCache(aNodeInstance, cache);
    const bool isEntity = TryBuildWorldEntityNodeCache(aNodeInstance, entityCache);
    const auto kind = GetWorldMeshSelectionKind(aNodeInstance);
    if (!isMesh && kind != WorldMeshSelectionKind::None)
        ++g_meshCacheFailures[static_cast<uint8_t>(kind)];
    if (!isEntity && IsEntityNodeInstance(aNodeInstance)) ++g_entityCacheFailures;
    if (isMesh)
    {
        static std::atomic<uint64_t> nextLog[5]{};
        if (DiagnosticDue(nextLog[static_cast<uint8_t>(kind)], 10000))
            Logging::Diagnostic("2.5 mesh tracked: type=%s kind=%u path=%llu bounds=%u root=%u broad=%u.",
                cache.definition->GetType()->GetName().ToString(), static_cast<uint32_t>(kind),
                cache.path.hash, cache.localBounds.IsValid() ? 1u : 0u,
                cache.rootDataValid ? 1u : 0u, cache.broadBoundsCount);
    }
    if (!isMesh && !isEntity)
    {
        return;
    }

    std::unique_lock lock(g_worldMeshNodesLock);
    bool changed = false;
    if (isMesh)
    {
        changed |= g_worldMeshNodes.emplace(aNodeInstance, std::move(cache)).second;
    }
    if (isEntity)
    {
        changed |= g_worldEntityNodes.emplace(aNodeInstance, std::move(entityCache)).second;
    }
    if (changed)
    {
        g_worldMeshNodesVersion.fetch_add(1, std::memory_order_release);
    }
}

void UntrackWorldMeshNode(RED4ext::worldINodeInstance* aNodeInstance)
{
    std::unique_lock lock(g_worldMeshNodesLock);
    const bool removedMesh = g_worldMeshNodes.erase(aNodeInstance) != 0;
    const bool removedEntity = g_worldEntityNodes.erase(aNodeInstance) != 0;
    if (removedMesh || removedEntity)
    {
        g_worldMeshNodesVersion.fetch_add(1, std::memory_order_release);
    }
    ClearWorldMeshSelection(aNodeInstance);
}

void WorldNodeInstanceAttachHook(RED4ext::worldINodeInstance* aNodeInstance, void* aContext)
{
    if (g_worldNodeInstanceAttachOriginal)
    {
        g_worldNodeInstanceAttachOriginal(aNodeInstance, aContext);
        TrackWorldMeshNode(aNodeInstance);
    }
}

void WorldNodeInstanceDetachHook(RED4ext::worldINodeInstance* aNodeInstance, void* aContext)
{
    UntrackWorldMeshNode(aNodeInstance);
    if (g_worldNodeInstanceDetachOriginal)
        g_worldNodeInstanceDetachOriginal(aNodeInstance, aContext);
}

bool AttachWorldNodeHooks()
{
    const auto* sdk = Logging::g_sdk;
    const auto handle = Logging::g_pluginHandle;
    if (!sdk || !sdk->hooking || !handle)
    {
        return false;
    }

    static RED4ext::UniversalRelocFunc<WorldNodeInstanceAttach_t> attachReloc(
        Addresses::WorldNodeInstanceAttach);
    static RED4ext::UniversalRelocFunc<WorldNodeInstanceAttach_t> detachReloc(
        Addresses::WorldNodeInstanceDetach);
    g_worldNodeInstanceAttachAddress = reinterpret_cast<void*>(static_cast<WorldNodeInstanceAttach_t>(attachReloc));
    g_worldNodeInstanceDetachAddress = reinterpret_cast<void*>(static_cast<WorldNodeInstanceAttach_t>(detachReloc));

    if (!g_worldNodeInstanceAttachAddress || !g_worldNodeInstanceDetachAddress)
    {
        Logging::Error("World mesh bounds registry unavailable: attach/detach addresses were not resolved.");
        return false;
    }

    if (!sdk->hooking->Attach(handle, g_worldNodeInstanceAttachAddress,
                              reinterpret_cast<void*>(&WorldNodeInstanceAttachHook),
                              reinterpret_cast<void**>(&g_worldNodeInstanceAttachOriginal)))
    {
        Logging::Error("World mesh bounds registry unavailable: node attach hook failed.");
        return false;
    }

    if (!sdk->hooking->Attach(handle, g_worldNodeInstanceDetachAddress,
                              reinterpret_cast<void*>(&WorldNodeInstanceDetachHook),
                              reinterpret_cast<void**>(&g_worldNodeInstanceDetachOriginal)))
    {
        sdk->hooking->Detach(handle, g_worldNodeInstanceAttachAddress);
        g_worldNodeInstanceAttachOriginal = nullptr;
        Logging::Error("World mesh bounds registry unavailable: node detach hook failed.");
        return false;
    }

    Logging::Info("World mesh bounds registry hooks attached.");
    return true;
}

void DetachWorldNodeHooks()
{
    const auto* sdk = Logging::g_sdk;
    const auto handle = Logging::g_pluginHandle;
    if (sdk && sdk->hooking && handle)
    {
        if (g_worldNodeInstanceDetachOriginal && g_worldNodeInstanceDetachAddress)
        {
            sdk->hooking->Detach(handle, g_worldNodeInstanceDetachAddress);
        }
        if (g_worldNodeInstanceAttachOriginal && g_worldNodeInstanceAttachAddress)
        {
            sdk->hooking->Detach(handle, g_worldNodeInstanceAttachAddress);
        }
    }

    g_worldNodeInstanceAttachOriginal = nullptr;
    g_worldNodeInstanceDetachOriginal = nullptr;
    g_worldNodeInstanceAttachAddress = nullptr;
    g_worldNodeInstanceDetachAddress = nullptr;
    std::unique_lock lock(g_worldMeshNodesLock);
    g_worldMeshNodes.clear();
    g_worldEntityNodes.clear();
    g_worldMeshNodesVersion.fetch_add(1, std::memory_order_release);
    ClearWorldMeshSelection();

    ClearInstanceResources();
}

bool IsExcluded(RED4ext::worldINodeInstance* aNodeInstance,
                const RED4ext::DynArray<RED4ext::WeakHandle<RED4ext::worldINodeInstance>>& aExcluded)
{
    for (const auto& excluded : aExcluded)
    {
        if (excluded.instance == aNodeInstance)
        {
            return true;
        }
    }
    return false;
}

bool TryReadWorldMeshInstance(RED4ext::worldINodeInstance* aNodeInstance,
                              RED4ext::Transform* aTransform, RED4ext::Vector3* aScale,
                              uint16_t* aState, RED4ext::Handle<RED4ext::CMesh>** aMesh)
{
    __try
    {
        *aTransform = *reinterpret_cast<RED4ext::Transform*>(
            reinterpret_cast<std::byte*>(aNodeInstance) + 0x30);
        *aScale = *reinterpret_cast<RED4ext::Vector3*>(
            reinterpret_cast<std::byte*>(aNodeInstance) + 0x50);
        *aState = *reinterpret_cast<uint16_t*>(reinterpret_cast<std::byte*>(aNodeInstance) + 0x8C);
        *aMesh = reinterpret_cast<RED4ext::Handle<RED4ext::CMesh>*>(
            reinterpret_cast<std::byte*>(aNodeInstance) + 0x98);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool TryReadWorldNodeOrientation(RED4ext::worldINodeInstance* aNodeInstance,
                                 RED4ext::Quaternion* aOrientation)
{
    __try
    {
        *aOrientation = reinterpret_cast<RED4ext::Transform*>(
                            reinterpret_cast<std::byte*>(aNodeInstance) + 0x30)
                            ->orientation;
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool IsWorldNodeAttachedAndVisible(RED4ext::worldINodeInstance* aNodeInstance)
{
    if (!aNodeInstance)
    {
        return false;
    }

    __try
    {
        const auto state = *reinterpret_cast<uint16_t*>(
            reinterpret_cast<std::byte*>(aNodeInstance) + 0x8C);
        constexpr uint16_t AttachedMask = 1u << 5u;
        constexpr uint16_t VisibleMask = 1u << 9u;
        return (state & AttachedMask) != 0 && (state & VisibleMask) != 0;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool TryGetLoadedMeshBounds(RED4ext::ResourcePath aPath, RED4ext::Box& aBounds)
{
    if (aPath.IsEmpty())
    {
        return false;
    }

    auto* loader = RED4ext::ResourceLoader::Get();
    auto token = loader ? loader->FindToken<RED4ext::CMesh>(aPath) : nullptr;
    if (!token || !token->IsLoaded() || !token->Get())
    {
        return false;
    }

    aBounds = token->Get()->boundingBox;
    return aBounds.IsValid();
}

// 2.5: MeshNodeInstance::LoadMesh and the cooked accessors use instance+0x88
// as the entry index. State flags moved to +0x8C. See docs/PATCH_2_5.md.
bool ReadCookedMeshIdentity(RED4ext::worldINodeInstance* instance,
                            RED4ext::ResourcePath& path, RED4ext::CName& appearance)
{
    auto* definition = GetWorldNodeDefinition(instance);
    if (!definition) return false;
    const auto kind = GetWorldMeshSelectionKind(instance);
    __try
    {
        auto* node = reinterpret_cast<const std::byte*>(definition);
        const auto index = *reinterpret_cast<const uint32_t*>(
            reinterpret_cast<const std::byte*>(instance) + 0x88);
        const std::byte* entry{};
        if (kind == WorldMeshSelectionKind::Instanced)
        {
            const auto count = *reinterpret_cast<const uint32_t*>(node + 0x7C);
            auto* entries = *reinterpret_cast<const std::byte* const*>(node + 0x70);
            if (!entries || index >= count) return false;
            entry = entries + static_cast<size_t>(index) * 0x40 + 0x20;
        }
        else if (kind == WorldMeshSelectionKind::Foliage)
        {
            entry = node + 0x38;
        }
        else if (kind == WorldMeshSelectionKind::Single ||
                 kind == WorldMeshSelectionKind::InstancedDestructible)
        {
            if (index == UINT32_MAX)
                entry = node + 0x38;
            else
            {
                const auto stride = *reinterpret_cast<const uint32_t*>(node + 0x50);
                const auto bytes = *reinterpret_cast<const uint32_t*>(node + 0x4C);
                auto* entries = *reinterpret_cast<const std::byte* const*>(node + 0x40);
                if (!entries || stride < 33 || stride > 256 || index >= bytes / stride)
                    return false;
                entry = entries + static_cast<size_t>(index) * stride;
            }
        }
        if (!entry) return false;
        std::memcpy(&path, entry, sizeof(path));
        std::memcpy(&appearance, entry + 8, sizeof(appearance));
        return !path.IsEmpty();
    }
    __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

RED4ext::ResourcePath GetWorldMeshPath(RED4ext::worldINodeInstance* instance)
{
    RED4ext::ResourcePath path{};
    RED4ext::CName appearance{};
    if (instance) ReadCookedMeshIdentity(instance, path, appearance);
    return path;
}

RED4ext::CName GetWorldMeshAppearance(RED4ext::worldINodeInstance* instance)
{
    RED4ext::ResourcePath path{};
    RED4ext::CName appearance{};
    if (instance) ReadCookedMeshIdentity(instance, path, appearance);
    return appearance;
}

bool IsPathExcluded(RED4ext::ResourcePath aPath,
                    const RED4ext::DynArray<RED4ext::ResourceAsyncReference<>>& aExcluded)
{
    for (const auto& excluded : aExcluded)
    {
        if (excluded.path == aPath)
        {
            return true;
        }
    }
    return false;
}

bool IntersectRayBox(const RED4ext::Vector4& aOrigin, const RED4ext::Vector4& aDirection,
                     const RED4ext::Box& aBox, float aMaxDistance, float& aDistance)
{
    float tMin = 0.0f;
    float tMax = aMaxDistance;
    const float origins[3] = {aOrigin.X, aOrigin.Y, aOrigin.Z};
    const float directions[3] = {aDirection.X, aDirection.Y, aDirection.Z};
    const float mins[3] = {aBox.Min.X, aBox.Min.Y, aBox.Min.Z};
    const float maxs[3] = {aBox.Max.X, aBox.Max.Y, aBox.Max.Z};

    for (uint32_t axis = 0; axis < 3; ++axis)
    {
        if (std::abs(directions[axis]) < 0.000001f)
        {
            if (origins[axis] < mins[axis] || origins[axis] > maxs[axis])
            {
                return false;
            }
            continue;
        }

        const float inverse = 1.0f / directions[axis];
        float nearDistance = (mins[axis] - origins[axis]) * inverse;
        float farDistance = (maxs[axis] - origins[axis]) * inverse;
        if (nearDistance > farDistance)
        {
            std::swap(nearDistance, farDistance);
        }
        tMin = std::max(tMin, nearDistance);
        tMax = std::min(tMax, farDistance);
        if (tMax < tMin)
        {
            return false;
        }
    }

    aDistance = tMin;
    return tMin <= aMaxDistance && tMax >= 0.0f;
}

} // namespace Detail

using namespace Detail;

bool Attach()
{
    return AttachWorldNodeHooks();
}

void Detach()
{
    DetachWorldNodeHooks();
}

bool SetVisible(const NodeHandle& aNode, bool aVisible)
{
    auto locked = aNode.Lock();
    if (!locked)
    {
        return false;
    }

    if (IsMeshNodeInstance(locked.GetPtr()))
    {
        const auto kind = GetWorldMeshSelectionKind(locked.GetPtr());
        if (kind == WorldMeshSelectionKind::InstancedDestructible)
        {
            WorldMeshSelection selection{};
            if (!aVisible &&
                (!ReadWorldMeshSelection(locked.GetPtr(), selection) || selection.count != 1))
            {
                return false;
            }

            using SetNodeVisibility = void (*)(RED4ext::worldINodeInstance*, bool);
            static RED4ext::UniversalRelocFunc<SetNodeVisibility> setVisibility(
                Addresses::WorldNodeInstanceSetVisibility);
            setVisibility(locked.GetPtr(), aVisible);
            return true;
        }

        if (kind == WorldMeshSelectionKind::Instanced ||
            kind == WorldMeshSelectionKind::Foliage)
        {
            // Grouped nodes share one aggregate proxy. Hiding it would hide every authored instance, not just the selected prop.
            WorldMeshSelection selection{};
            ReadWorldMeshSelection(locked.GetPtr(), selection);
#if EXAMINE_INTERACTION_PROFILE_NATIVE
            Logging::Diagnostic("Grouped world mesh visibility left unchanged: kind=%u index=%d count=%d visible=%u.",
                          static_cast<uint32_t>(kind), selection.index, selection.count,
                          aVisible ? 1u : 0u);
#endif
            return false;
        }

        auto* renderProxy = reinterpret_cast<RED4ext::SharedPtr<RenderProxy>*>(
            reinterpret_cast<std::byte*>(locked.GetPtr()) + Addresses::MeshRenderProxyOffset);
        if (!renderProxy || !*renderProxy)
        {
            return false;
        }

        using SetRenderProxyVisibility = void (*)(RenderProxy*, bool);
        static RED4ext::UniversalRelocFunc<SetRenderProxyVisibility> setVisibility(
            Addresses::RenderProxySetVisibility);
        setVisibility(renderProxy->GetPtr(), aVisible);
        Logging::Diagnostic("World mesh render-proxy visibility set: instance=%p visible=%u.",
                      locked.GetPtr(), aVisible ? 1u : 0u);
        return true;
    }

    using SetNodeVisibility = void (*)(RED4ext::worldINodeInstance*, bool);
    static RED4ext::UniversalRelocFunc<SetNodeVisibility> setVisibility(
        Addresses::WorldNodeInstanceSetVisibility);
    setVisibility(locked.GetPtr(), aVisible);
#if EXAMINE_INTERACTION_PROFILE_NATIVE
    Logging::Diagnostic("World node visibility set through node state: instance=%p visible=%u.",
                  locked.GetPtr(), aVisible ? 1u : 0u);
#endif
    return true;
}

RED4ext::Box GetLocalBounds(const NodeHandle& aNode)
{
    RED4ext::Box result{};
    auto locked = aNode.Lock();
    if (!locked)
    {
        return result;
    }

    WorldMeshSelection selection{};
    if (ReadWorldMeshSelection(locked.GetPtr(), selection) && selection.localBounds.IsValid())
    {
        return selection.localBounds;
    }

    RED4ext::Transform transform{};
    RED4ext::Vector3 scale{};
    RED4ext::Handle<RED4ext::CMesh>* meshHandle{};
    uint16_t state{};
    if (TryReadWorldMeshInstance(locked.GetPtr(), &transform, &scale, &state, &meshHandle) &&
        meshHandle && *meshHandle)
    {
        // The preview component is created at identity, so return resource-local bounds.
        result = (*meshHandle)->boundingBox;
    }
    return result;
}

RED4ext::Quaternion GetOrientation(const NodeHandle& aNode)
{
    RED4ext::Quaternion result{};
    result.r = 1.0f;
    auto locked = aNode.Lock();
    if (!locked)
    {
        return result;
    }

    WorldMeshSelection selection{};
    if (ReadWorldMeshSelection(locked.GetPtr(), selection))
    {
        return selection.orientation;
    }

    TryReadWorldNodeOrientation(locked.GetPtr(), &result);
    return result;
}

RED4ext::Vector3 GetScale(const NodeHandle& aNode)
{
    RED4ext::Vector3 result{1.0f, 1.0f, 1.0f};
    auto locked = aNode.Lock();
    if (!locked)
    {
        return result;
    }

    WorldMeshSelection selection{};
    if (ReadWorldMeshSelection(locked.GetPtr(), selection))
    {
        return selection.scale;
    }

    RED4ext::Transform transform{};
    uint16_t state{};
    RED4ext::Handle<RED4ext::CMesh>* meshHandle{};
    TryReadWorldMeshInstance(locked.GetPtr(), &transform, &result, &state, &meshHandle);
    return result;
}

RED4ext::CName GetAppearance(const NodeHandle& aNode)
{
    auto locked = aNode.Lock();
    if (!locked)
    {
        return {};
    }

    WorldMeshSelection selection{};
    if (ReadWorldMeshSelection(locked.GetPtr(), selection))
    {
        return selection.appearance;
    }
    return GetWorldMeshAppearance(locked.GetPtr());
}

bool IsGrouped(const NodeHandle& aNode)
{
    auto locked = aNode.Lock();
    const auto kind = locked ? GetWorldMeshSelectionKind(locked.GetPtr())
                             : WorldMeshSelectionKind::None;
    if (kind == WorldMeshSelectionKind::InstancedDestructible)
    {
        WorldMeshSelection selection{};
        return !ReadWorldMeshSelection(locked.GetPtr(), selection) || selection.count != 1;
    }
    return kind == WorldMeshSelectionKind::Instanced ||
           kind == WorldMeshSelectionKind::Foliage;
}

bool IsAdvertisement(const NodeHandle& aNode)
{
    auto locked = aNode.Lock();
    return locked && Detail::GetAdvertisementDefinition(locked.GetPtr());
}

int32_t GetSelectionIndex(const NodeHandle& aNode)
{
    auto locked = aNode.Lock();
    WorldMeshSelection selection{};
    return locked && ReadWorldMeshSelection(locked.GetPtr(), selection) ? selection.index : -1;
}

int32_t GetSelectionCount(const NodeHandle& aNode)
{
    auto locked = aNode.Lock();
    WorldMeshSelection selection{};
    return locked && ReadWorldMeshSelection(locked.GetPtr(), selection) ? selection.count : 0;
}

NodeHandle FindNode(RED4ext::Vector4 aOrigin, RED4ext::Vector4 aDirection,
                    float aMaxDistance, const NodeArray& aExcluded)
{
    const float length = std::sqrt(aDirection.X * aDirection.X +
                                   aDirection.Y * aDirection.Y +
                                   aDirection.Z * aDirection.Z);
    if (length < 0.000001f || aMaxDistance <= 0.0f)
    {
        return {};
    }

    aDirection.X /= length;
    aDirection.Y /= length;
    aDirection.Z /= length;
    aDirection.W = 0.0f;

    float nearestDistance = std::numeric_limits<float>::max();
    NodeHandle nearest;
    RED4ext::worldINodeInstance* nearestInstance = nullptr;
    WorldMeshSelection nearestSelection{};
    uint32_t tested = 0;
    uint32_t intersected = 0;
    std::size_t tracked = 0;

    {
        std::shared_lock lock(g_worldMeshNodesLock);
        tracked = g_worldMeshNodes.size();
        for (const auto& [instance, cache] : g_worldMeshNodes)
        {
            if (!instance || IsExcluded(instance, aExcluded))
            {
                continue;
            }

            ++tested;
            WorldMeshSelection selection{};
            float distance = 0.0f;
            if (TrySelectWorldMeshInstance(instance, aOrigin, aDirection, aMaxDistance,
                                           selection, distance, nullptr, &cache))
            {
                ++intersected;
                if (distance < nearestDistance)
                {
                    nearestDistance = distance;
                    nearestInstance = instance;
                    nearestSelection = selection;
                }
            }
        }

        if (nearestInstance)
        {
            nearest = ToWeakHandle(nearestInstance);
        }
    }

    if (nearest)
    {
        StoreWorldMeshSelection(nearestSelection);
    }
    else
    {
        ClearWorldMeshSelection();
    }

#if EXAMINE_INTERACTION_PROFILE_NATIVE
    static std::atomic<uint32_t> queryCount{};
    const auto query = queryCount.fetch_add(1, std::memory_order_relaxed) + 1;
    if (query <= 8 || (query % 50) == 0)
    {
        Logging::Diagnostic("World mesh bounds query: tracked=%llu tested=%u intersected=%u excluded=%u found=%u distance=%.3f.",
                      static_cast<unsigned long long>(tracked), tested, intersected,
                      aExcluded.Size(), nearest ? 1u : 0u,
                      nearest ? nearestDistance : -1.0f);
    }
#endif
    return nearest;
}

EntityHandle FindEntity(RED4ext::Vector4 aOrigin, RED4ext::Vector4 aDirection,
                        float aMaxDistance, const EntityArray& aExcluded)
{
    const float length = std::sqrt(aDirection.X * aDirection.X +
                                   aDirection.Y * aDirection.Y +
                                   aDirection.Z * aDirection.Z);
    if (length < 0.000001f || aMaxDistance <= 0.0f)
    {
        return {};
    }

    aDirection.X /= length;
    aDirection.Y /= length;
    aDirection.Z /= length;
    aDirection.W = 0.0f;

    float nearestDistance = std::numeric_limits<float>::max();
    float nearestAimError = std::numeric_limits<float>::max();
    RED4ext::entEntity* nearest{};
    uint32_t tested{};
    uint32_t hidden{};
    uint32_t missingHandle{};
    uint32_t intersected{};
    std::size_t tracked{};
    {
        std::shared_lock lock(g_worldMeshNodesLock);
        tracked = g_worldEntityNodes.size();
        for (const auto& [instance, cache] : g_worldEntityNodes)
        {
            if (!instance || !IsWorldNodeAttachedAndVisible(instance))
            {
                ++hidden;
                continue;
            }

            auto* entity = GetWorldEntity(instance);
            if (!entity)
            {
                ++missingHandle;
                continue;
            }

            bool excluded = false;
            for (const auto& item : aExcluded)
            {
                if (item.instance == entity)
                {
                    excluded = true;
                    break;
                }
            }
            if (excluded)
            {
                continue;
            }

            ++tested;
            float distance{};
            if (IntersectRayBox(aOrigin, aDirection, cache.worldBounds, aMaxDistance, distance))
            {
                ++intersected;
                // Several apartment display entities have broad, overlapping AABBs (and the camera can even begin inside one). Entry distance alone then makes a lower object dominate the whole wall. Rank intersected candidates by the angular miss of their bounds center from the camera ray, with depth only as the tie-breaker. This matches what the crosshair points at.
                const RED4ext::Vector4 center{
                    (cache.worldBounds.Min.X + cache.worldBounds.Max.X) * 0.5f,
                    (cache.worldBounds.Min.Y + cache.worldBounds.Max.Y) * 0.5f,
                    (cache.worldBounds.Min.Z + cache.worldBounds.Max.Z) * 0.5f,
                    1.0f};
                const float deltaX = center.X - aOrigin.X;
                const float deltaY = center.Y - aOrigin.Y;
                const float deltaZ = center.Z - aOrigin.Z;
                const float along = deltaX * aDirection.X +
                                    deltaY * aDirection.Y +
                                    deltaZ * aDirection.Z;
                const float projected = std::max(along, 0.01f);
                const float offsetX = deltaX - aDirection.X * projected;
                const float offsetY = deltaY - aDirection.Y * projected;
                const float offsetZ = deltaZ - aDirection.Z * projected;
                const float aimError = (offsetX * offsetX + offsetY * offsetY + offsetZ * offsetZ) /
                                       (projected * projected);

                if (aimError < nearestAimError - 0.000001f ||
                    (std::abs(aimError - nearestAimError) <= 0.000001f && distance < nearestDistance))
                {
                    nearestAimError = aimError;
                    nearestDistance = distance;
                    nearest = entity;
                }
            }
        }
    }

    static std::atomic<uint64_t> nextEntityLog{};
    if (DiagnosticDue(nextEntityLog, 5000))
        Logging::Diagnostic("2.5 entity query: tracked=%llu cacheFailed=%llu hidden=%u handleMissing=%u tested=%u intersected=%u excluded=%u found=%u distance=%.3f aimError=%.6f.",
            static_cast<unsigned long long>(tracked),
            static_cast<unsigned long long>(g_entityCacheFailures.load()), hidden, missingHandle, tested, intersected,
            aExcluded.Size(), nearest ? 1u : 0u, nearest ? nearestDistance : -1.0f,
            nearest ? nearestAimError : -1.0f);

    return ToWeakHandle(nearest);
}

PathReference FindPath(RED4ext::Vector4 aOrigin, RED4ext::Vector4 aDirection,
                       float aMaxDistance, const PathArray& aExcluded)
{
#if EXAMINE_INTERACTION_PROFILE_NATIVE
    const auto profileStart = ProfileClock::now();
    uint64_t cacheWaitNs{};
    uint64_t nodesWaitNs{};
    uint64_t scanNs{};
    uint64_t sortNs{};
#endif
    PathReference result{};
    ClearWorldMeshSelection();

    const float length = std::sqrt(aDirection.X * aDirection.X +
                                   aDirection.Y * aDirection.Y +
                                   aDirection.Z * aDirection.Z);
    if (length < 0.000001f || aMaxDistance <= 0.0f)
    {
        return result;
    }

    aDirection.X /= length;
    aDirection.Y /= length;
    aDirection.Z /= length;
    aDirection.W = 0.0f;

#if EXAMINE_INTERACTION_PROFILE_NATIVE
    const auto cacheWaitStart = ProfileClock::now();
#endif
    std::unique_lock cacheLock(g_worldMeshRayCacheLock);
#if EXAMINE_INTERACTION_PROFILE_NATIVE
    cacheWaitNs = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
        ProfileClock::now() - cacheWaitStart).count());
    const auto nodesWaitStart = ProfileClock::now();
#endif
    std::shared_lock nodesLock(g_worldMeshNodesLock);
#if EXAMINE_INTERACTION_PROFILE_NATIVE
    nodesWaitNs = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
        ProfileClock::now() - nodesWaitStart).count());
#endif
    const auto nodesVersion = g_worldMeshNodesVersion.load(std::memory_order_acquire);
    const bool sameRay = g_worldMeshRayCache.valid &&
                         g_worldMeshRayCache.nodesVersion == nodesVersion &&
                         g_worldMeshRayCache.maxDistance == aMaxDistance &&
                         g_worldMeshRayCache.origin.X == aOrigin.X &&
                         g_worldMeshRayCache.origin.Y == aOrigin.Y &&
                         g_worldMeshRayCache.origin.Z == aOrigin.Z &&
                         g_worldMeshRayCache.direction.X == aDirection.X &&
                         g_worldMeshRayCache.direction.Y == aDirection.Y &&
                         g_worldMeshRayCache.direction.Z == aDirection.Z;

    uint32_t tested = 0;
    WorldMeshProbeStats probeStats{};
    if (!sameRay)
    {
        g_worldMeshRayCache.valid = true;
        g_worldMeshRayCache.origin = aOrigin;
        g_worldMeshRayCache.direction = aDirection;
        g_worldMeshRayCache.maxDistance = aMaxDistance;
        g_worldMeshRayCache.nodesVersion = nodesVersion;
        g_worldMeshRayCache.hits.clear();

#if EXAMINE_INTERACTION_PROFILE_NATIVE
        const auto scanStart = ProfileClock::now();
#endif
        for (const auto& [instance, cache] : g_worldMeshNodes)
        {
            if (!instance)
            {
                continue;
            }

            ++tested;
            WorldMeshSelection selection{};
            float distance = 0.0f;
            if (TrySelectWorldMeshInstance(instance, aOrigin, aDirection, aMaxDistance,
                                            selection, distance, &probeStats, &cache))
            {
                g_worldMeshRayCache.hits.push_back({selection, distance});
            }
        }
#if EXAMINE_INTERACTION_PROFILE_NATIVE
        scanNs = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
            ProfileClock::now() - scanStart).count());
        const auto sortStart = ProfileClock::now();
#endif

        static std::atomic<uint64_t> nextProbeLog{};
        if (DiagnosticDue(nextProbeLog, 5000))
        {
            Logging::Diagnostic("2.5 mesh query: nodes(single=%u instanced=%u destructible=%u foliage=%u) cacheFailed(single=%llu instanced=%llu destructible=%llu foliage=%llu) hits=%llu.",
                probeStats.singleNodes, probeStats.instancedNodes, probeStats.instancedDestructibleNodes, probeStats.foliageNodes,
                g_meshCacheFailures[1].load(), g_meshCacheFailures[3].load(),
                g_meshCacheFailures[2].load(), g_meshCacheFailures[4].load(),
                static_cast<unsigned long long>(g_worldMeshRayCache.hits.size()));
            Logging::Diagnostic("2.5 foliage probe: nodes=%u hidden=%u rootFailed=%u boundsMissing=%u populationUnavailable=%u rayMiss=%u selected=%u testedInstances=%llu.",
                probeStats.foliageNodes, probeStats.foliageNotVisible, probeStats.foliageRootReadFailed,
                probeStats.foliageBoundsUnavailable, probeStats.foliagePopulationUnavailable,
                probeStats.foliageNoIntersection, probeStats.foliageSelected, probeStats.foliageInstanceTests);
            Logging::Diagnostic("2.5 destructible probe: nodes=%u hidden=%u boundsMissing=%u transformsUnavailable=%u selected=%u testedInstances=%llu.",
                probeStats.instancedDestructibleNodes, probeStats.destructibleHidden,
                probeStats.destructibleBoundsUnavailable, probeStats.destructibleTransformsUnavailable,
                probeStats.destructibleSelected, probeStats.instancedDestructibleInstanceTests);
        }

        std::sort(g_worldMeshRayCache.hits.begin(), g_worldMeshRayCache.hits.end(),
                  [](const WorldMeshRayHit& aLeft, const WorldMeshRayHit& aRight) {
                       return aLeft.distance < aRight.distance;
                   });
#if EXAMINE_INTERACTION_PROFILE_NATIVE
        sortNs = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
            ProfileClock::now() - sortStart).count());
#endif

#if EXAMINE_INTERACTION_PROFILE_NATIVE
        static std::atomic<uint32_t> buildCount{};
        const auto build = buildCount.fetch_add(1, std::memory_order_relaxed) + 1;
        if (build <= 4 || (build % 100) == 0)
        {
            Logging::Diagnostic("World mesh ray cache rebuilt: tracked=%llu tested=%u hits=%llu.",
                          static_cast<unsigned long long>(g_worldMeshNodes.size()), tested,
                          static_cast<unsigned long long>(g_worldMeshRayCache.hits.size()));
            if (probeStats.foliageNodes != 0)
            {
                Logging::Diagnostic("Foliage ray diagnostics: tracked=%u hidden=%u root=%u bounds=%u population=%u miss=%u selected=%u.",
                              probeStats.foliageNodes, probeStats.foliageNotVisible,
                              probeStats.foliageRootReadFailed, probeStats.foliageBoundsUnavailable,
                              probeStats.foliagePopulationUnavailable,
                              probeStats.foliageNoIntersection,
                              probeStats.foliageSelected);
            }
        }
#endif
    }

    for (const auto& hit : g_worldMeshRayCache.hits)
    {
        if (!hit.selection.node || IsPathExcluded(hit.selection.path, aExcluded) ||
            !g_worldMeshNodes.contains(hit.selection.node))
        {
            continue;
        }

        StoreWorldMeshSelection(hit.selection);
        result.path = hit.selection.path;
        break;
    }
#if EXAMINE_INTERACTION_PROFILE_NATIVE
    NativeQueryProfileSample profileSample{};
    profileSample.cacheHit = sameRay;
    profileSample.selected = !result.path.IsEmpty();
    profileSample.tracked = g_worldMeshNodes.size();
    profileSample.tested = tested;
    profileSample.hits = g_worldMeshRayCache.hits.size();
    profileSample.totalNs = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            ProfileClock::now() - profileStart).count());
    profileSample.cacheWaitNs = cacheWaitNs;
    profileSample.nodesWaitNs = nodesWaitNs;
    profileSample.scanNs = scanNs;
    profileSample.sortNs = sortNs;
    profileSample.workload = probeStats;
    RecordNativeQueryProfile(profileSample);
#endif
    return result;
}

NodeHandle AcquireCandidate()
{
    auto* instance = g_lastWorldMeshCandidate.load(std::memory_order_acquire);
    if (!instance)
    {
        return {};
    }

    std::shared_lock lock(g_worldMeshNodesLock);
    if (!g_worldMeshNodes.contains(instance)) return {};
    WorldMeshSelection selection;
    static std::atomic<uint64_t> nextAcquiredLog{};
    if (ReadWorldMeshSelection(instance, selection) && DiagnosticDue(nextAcquiredLog, 1000))
        LogMeshDiagnostic("acquired", selection);
    return ToWeakHandle(instance);
}
} // namespace ExamineInteractionNative::World

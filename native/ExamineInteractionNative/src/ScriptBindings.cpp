#include "Dof/DofOverride.hpp"
#include "Interaction/LootChoice.hpp"
#include "World/WorldMesh.hpp"

#include <RedLib.hpp>

namespace ExamineInteractionNative::Bindings
{
bool ExamineInteractionNativeSetDof(float aIntensity, float aNearBlur, float aNearFocus,
                                    float aFarBlur, float aFarFocus,
                                    bool aUseNearPlane, bool aUseFarPlane)
{
    return Dof::Set(aIntensity, aNearBlur, aNearFocus, aFarBlur, aFarFocus,
                    aUseNearPlane, aUseFarPlane);
}

bool ExamineInteractionNativeResetDof()
{
    return Dof::Reset();
}

bool ExamineInteractionNativePrepareLootChoiceEvent(
    const RED4ext::Handle<RED4ext::game::interactions::ChoiceEvent>& aEvent,
    RED4ext::ItemID aItemID, RED4ext::CName aAction,
    bool aRemoveItem, bool aIllegal)
{
    return Interaction::PrepareLootChoiceEvent(
        aEvent, aItemID, aAction, aRemoveItem, aIllegal);
}

bool ExamineInteractionNativePublishLootChoiceEvent(
    const RED4ext::Handle<RED4ext::game::interactions::ChoiceEvent>& aEvent,
    int32_t aChoiceIndex)
{
    return Interaction::PublishLootChoiceEvent(aEvent, aChoiceIndex);
}

bool ExamineInteractionNativeSetWorldNodeVisible(World::NodeHandle aNode, bool aVisible)
{
    return World::SetVisible(aNode, aVisible);
}

RED4ext::Box ExamineInteractionNativeGetWorldNodeLocalBounds(World::NodeHandle aNode)
{
    return World::GetLocalBounds(aNode);
}

RED4ext::Quaternion ExamineInteractionNativeGetWorldNodeOrientation(World::NodeHandle aNode)
{
    return World::GetOrientation(aNode);
}

RED4ext::CName ExamineInteractionNativeGetWorldNodeAppearance(World::NodeHandle aNode)
{
    return World::GetAppearance(aNode);
}

bool ExamineInteractionNativeIsWorldNodeGrouped(World::NodeHandle aNode)
{
    return World::IsGrouped(aNode);
}

int32_t ExamineInteractionNativeGetWorldNodeSelectionIndex(World::NodeHandle aNode)
{
    return World::GetSelectionIndex(aNode);
}

int32_t ExamineInteractionNativeGetWorldNodeSelectionCount(World::NodeHandle aNode)
{
    return World::GetSelectionCount(aNode);
}

World::NodeHandle ExamineInteractionNativeFindWorldMeshNode(
    RED4ext::Vector4 aOrigin, RED4ext::Vector4 aDirection, float aMaxDistance,
    const World::NodeArray& aExcluded)
{
    return World::FindNode(aOrigin, aDirection, aMaxDistance, aExcluded);
}

World::EntityHandle ExamineInteractionNativeFindWorldEntity(
    RED4ext::Vector4 aOrigin, RED4ext::Vector4 aDirection, float aMaxDistance,
    const World::EntityArray& aExcluded)
{
    return World::FindEntity(aOrigin, aDirection, aMaxDistance, aExcluded);
}

World::PathReference ExamineInteractionNativeFindWorldMeshPath(
    RED4ext::Vector4 aOrigin, RED4ext::Vector4 aDirection, float aMaxDistance,
    const World::PathArray& aExcluded)
{
    return World::FindPath(aOrigin, aDirection, aMaxDistance, aExcluded);
}

World::NodeHandle ExamineInteractionNativeAcquireWorldMeshCandidate()
{
    return World::AcquireCandidate();
}
}

RTTI_DEFINE_GLOBALS(ExamineInteractionNative::Bindings, {
    RTTI_FUNCTION(ExamineInteractionNativeSetDof,
        "MisterChedda.ExamineInteraction.Native.SetDof");
    RTTI_FUNCTION(ExamineInteractionNativeResetDof,
        "MisterChedda.ExamineInteraction.Native.ResetDof");
    RTTI_FUNCTION(ExamineInteractionNativePrepareLootChoiceEvent,
        "MisterChedda.ExamineInteraction.Native.PrepareLootChoiceEvent");
    RTTI_FUNCTION(ExamineInteractionNativePublishLootChoiceEvent,
        "MisterChedda.ExamineInteraction.Native.PublishLootChoiceEvent");
    RTTI_FUNCTION(ExamineInteractionNativeSetWorldNodeVisible,
        "MisterChedda.ExamineInteraction.Native.SetWorldNodeVisible");
    RTTI_FUNCTION(ExamineInteractionNativeGetWorldNodeLocalBounds,
        "MisterChedda.ExamineInteraction.Native.GetWorldNodeLocalBounds");
    RTTI_FUNCTION(ExamineInteractionNativeGetWorldNodeOrientation,
        "MisterChedda.ExamineInteraction.Native.GetWorldNodeOrientation");
    RTTI_FUNCTION(ExamineInteractionNativeGetWorldNodeAppearance,
        "MisterChedda.ExamineInteraction.Native.GetWorldNodeAppearance");
    RTTI_FUNCTION(ExamineInteractionNativeIsWorldNodeGrouped,
        "MisterChedda.ExamineInteraction.Native.IsWorldNodeGrouped");
    RTTI_FUNCTION(ExamineInteractionNativeGetWorldNodeSelectionIndex,
        "MisterChedda.ExamineInteraction.Native.GetWorldNodeSelectionIndex");
    RTTI_FUNCTION(ExamineInteractionNativeGetWorldNodeSelectionCount,
        "MisterChedda.ExamineInteraction.Native.GetWorldNodeSelectionCount");
    RTTI_FUNCTION(ExamineInteractionNativeFindWorldMeshNode,
        "MisterChedda.ExamineInteraction.Native.FindWorldMeshNode");
    RTTI_FUNCTION(ExamineInteractionNativeFindWorldEntity,
        "MisterChedda.ExamineInteraction.Native.FindWorldEntity");
    RTTI_FUNCTION(ExamineInteractionNativeFindWorldMeshPath,
        "MisterChedda.ExamineInteraction.Native.FindWorldMeshPath");
    RTTI_FUNCTION(ExamineInteractionNativeAcquireWorldMeshCandidate,
        "MisterChedda.ExamineInteraction.Native.AcquireWorldMeshCandidate");
});

#pragma once

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/Box.hpp>
#include <RED4ext/Scripting/Natives/Vector4.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/Entity.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/INodeInstance.hpp>

namespace ExamineInteractionNative::World
{
using NodeHandle = RED4ext::WeakHandle<RED4ext::worldINodeInstance>;
using NodeArray = RED4ext::DynArray<NodeHandle>;
using EntityHandle = RED4ext::WeakHandle<RED4ext::entEntity>;
using EntityArray = RED4ext::DynArray<EntityHandle>;
using PathReference = RED4ext::ResourceAsyncReference<>;
using PathArray = RED4ext::DynArray<PathReference>;

bool Attach();
void Detach();

bool SetVisible(const NodeHandle& aNode, bool aVisible);
RED4ext::Box GetLocalBounds(const NodeHandle& aNode);
RED4ext::Quaternion GetOrientation(const NodeHandle& aNode);
RED4ext::Vector3 GetScale(const NodeHandle& aNode);
RED4ext::CName GetAppearance(const NodeHandle& aNode);
bool IsAdvertisement(const NodeHandle& aNode);
bool IsGrouped(const NodeHandle& aNode);
int32_t GetSelectionIndex(const NodeHandle& aNode);
int32_t GetSelectionCount(const NodeHandle& aNode);
NodeHandle FindNode(RED4ext::Vector4 aOrigin, RED4ext::Vector4 aDirection,
                    float aMaxDistance, const NodeArray& aExcluded);
EntityHandle FindEntity(RED4ext::Vector4 aOrigin, RED4ext::Vector4 aDirection,
                        float aMaxDistance, const EntityArray& aExcluded);
PathReference FindPath(RED4ext::Vector4 aOrigin, RED4ext::Vector4 aDirection,
                       float aMaxDistance, const PathArray& aExcluded);
NodeHandle AcquireCandidate();
}

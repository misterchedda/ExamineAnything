#pragma once

#include <RED4ext/Handle.hpp>
#include <RED4ext/NativeTypes.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/interactions/ChoiceEvent.hpp>

namespace ExamineInteractionNative::Interaction
{
bool Attach();
void Detach();

bool PrepareLootChoiceEvent(
    const RED4ext::Handle<RED4ext::game::interactions::ChoiceEvent>& aEvent,
    RED4ext::ItemID aItemID, RED4ext::CName aAction,
    bool aRemoveItem, bool aIllegal);

void CancelLootChoiceEvent(
    const RED4ext::Handle<RED4ext::game::interactions::ChoiceEvent>& aEvent);

bool PublishLootChoiceEvent(
    const RED4ext::Handle<RED4ext::game::interactions::ChoiceEvent>& aEvent,
    int32_t aChoiceIndex);
}

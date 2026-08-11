module MisterChedda.ExamineInteraction

import Codeware.UI.*
import MisterChedda.ExamineInteraction.Native.*

public class ExamineInteractionService extends ScriptableService {
  private let m_controller: wref<LootingGameController>;
  private let m_examineInteractionVisible: Bool;
  private let m_examineInteractionData: LootData;
  private let m_examineInteractionLastUnsupported: TweakDBID;
  private let m_examineClothingToken: ref<ResourceToken>;
  private let m_examineClothingTemplatePath: ResRef;
  private let m_examineClothingBaseAppearance: CName;
  private let m_examineClothingGender: CName;
  private let m_examineClothingEntityName: CName;
  private let m_examineClothingItemID: ItemID;
  private let m_examineClothingItemData: wref<gameItemData>;
  private let m_examineClothingActionContext: ref<ExamineInteractionLootActionContext>;
  private let m_examineGenericToken: ref<ResourceToken>;
  private let m_examineGenericTemplatePath: ResRef;
  private let m_examineGenericAppearance: CName;
  private let m_examineGenericEntityName: CName;
  private let m_examineGenericItemID: ItemID;
  private let m_examineGenericItemData: wref<gameItemData>;
  private let m_examineGenericQuantity: Int32;
  private let m_examineGenericActionContext: ref<ExamineInteractionLootActionContext>;
  private let m_examinePropFocusHeld: Bool;
  private let m_examinePropFocusGeneration: Uint32;
  private let m_examinePropCandidate: wref<worldINodeInstance>;
  private let m_examinePropCandidateID: EntityID;
  private let m_examineEntityCandidate: wref<Entity>;
  private let m_examineEntityTemplatePath: ResRef;
  private let m_examinePropMeshPath: ResRef;
  private let m_examinePropMeshAppearance: CName;
  private let m_examinePropFocusPolls: Int32;
  private let m_examinePropStablePolls: Int32;
  private let m_examinePropMissPolls: Int32;
  private let m_examinePropPromptVisible: Bool;
  private let m_examinePropDiagnosticLogged: Bool;
  private let m_examineKey: EInputKey;
  private let m_examineItemPreviewFactory: ref<ExamineInteractionWeaponPreviewFactory>;

  private cb func OnLoad() {
    this.m_examineKey = this.ResolveExamineKey();
    this.RegisterInputBindings();
    GameInstance.GetCallbackSystem().RegisterCallback(n"Session/End", this, n"OnSessionEnd");
  }

  private cb func OnSessionEnd(event: ref<GameSessionEvent>) {
    this.DetachController();
  }

  public static func Get() -> ref<ExamineInteractionService> {
    return GameInstance
      .GetScriptableServiceContainer()
      .GetService(n"MisterChedda.ExamineInteraction.ExamineInteractionService") as ExamineInteractionService;
  }

  private final func GetSettings() -> ref<ExamineInteractionSettings> {
    return ExamineInteractionSettings.Get(GetGameInstance());
  }

  public final func IsEnabled() -> Bool {
    let settings = this.GetSettings();
    return !IsDefined(settings) || settings.enabled;
  }

  private final func ResolveExamineKey() -> EInputKey {
    let settings = this.GetSettings();
    if IsDefined(settings) && NotEquals(settings.examineKey, EInputKey.IK_None) {
      return settings.examineKey;
    }
    return EInputKey.IK_G;
  }

  private final func RegisterInputBindings() -> Void {
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Input/Key", this, n"OnExamineInteractionKey")
      .AddTarget(InputTarget.Key(this.m_examineKey, EInputAction.IACT_Release))
      .AddTarget(InputTarget.Key(EInputKey.IK_RightMouse));
  }

  private final func RefreshInputBindings() -> Void {
    GameInstance.GetCallbackSystem()
      .UnregisterCallback(n"Input/Key", this, n"OnExamineInteractionKey");
    this.m_examineKey = this.ResolveExamineKey();
    this.RegisterInputBindings();
  }

  public final func OnSettingsChanged() -> Void {
    let dof: ref<ExamineInteractionSceneDOF>;
    this.RefreshInputBindings();
    if IsDefined(this.m_controller) {
      this.m_controller.ExamineInteractionSetWorldPropPrompt(
        this.m_examinePropPromptVisible,
        this.m_examineKey
      );
    }

    if !this.IsEnabled() {
      this.ExamineInteractionStopPropFocus("settings disabled");
      this.m_examineInteractionVisible = false;
    }

    if IsDefined(this.GetSettings())
      && (!this.GetSettings().previewDofEnabled || this.GetSettings().previewDofStrength <= 0.0) {
      dof = GameInstance.GetScriptableServiceContainer()
        .GetService(n"MisterChedda.ExamineInteraction.ExamineInteractionSceneDOF") as ExamineInteractionSceneDOF;
      if IsDefined(dof) {
        dof.Reset();
      }
    }

    FTLog(s"[ExamineInteraction] Settings applied: enabled=\(this.IsEnabled()) examineKey=\(EnumInt(this.m_examineKey)) diagnosticLogging=\(ExamineInteractionLog.DiagnosticsEnabled())");
  }

  public final func AttachController(controller: wref<LootingGameController>) -> Void {
    this.m_controller = controller;
    if IsDefined(controller) {
      controller.ExamineInteractionSetWorldPropPrompt(
        this.m_examinePropPromptVisible,
        this.m_examineKey
      );
    }
  }

  public final func ShowWorldEntity(sourceEntity: wref<Entity>) -> Void {
    let player = this.GetPlayer();

    if !this.IsEnabled() || !IsDefined(sourceEntity) {
      return;
    }
    if !IsDefined(this.m_controller) {
      FTLog("[ExamineInteraction] World-entity inspection could not open: the HUD requester is unavailable.");
      return;
    }

    if StrBeginsWith(
      ResRef.ToString(sourceEntity.GetTemplatePath()),
      "base\\quest\\minor_quests\\mq000\\entities\\stash_weapons\\"
    ) && IsDefined(player) {
      GameObject.PlaySoundEvent(player, n"cmn_generic_metal_foley");
    } else {
      this.PlayExamineFallbackSound();
    }
    ExamineInteractionPopup.ShowWorldEntity(sourceEntity, this.m_controller);
  }

  public final func DetachController() -> Void {
    this.ExamineInteractionStopPropFocus("looting controller detached");
    if IsDefined(this.m_examineItemPreviewFactory) {
      this.m_examineItemPreviewFactory.Abort();
      this.m_examineItemPreviewFactory = null;
    }
    this.m_examineInteractionVisible = false;
    this.m_controller = null;
  }

  private final func GetPlayer() -> ref<PlayerPuppet> {
    return GameInstance.GetPlayerSystem(GetGameInstance()).GetPlayer();
  }

  private final func PlayExamineFallbackSound() -> Void {
    let player = this.GetPlayer();
    if IsDefined(player) {
      GameObject.PlaySoundEvent(player, n"inv_loot_generic");
    }
  }

  private final func PlayExamineWorldMeshSound(meshPath: ResRef) -> Void {
    let eventName: CName;
    let path = StrLower(ResRef.ToString(meshPath));
    let player = this.GetPlayer();
    let variation: Int32;

    if !IsDefined(player) {
      return;
    }

    if StrContains(path, "decoration\\food\\drinks\\") {
      eventName = n"g_sc_npc_work_grab_can";
    } else if StrContains(path, "decoration\\food\\") {
      eventName = n"cmn_generic_work_food_takeout";
    } else if StrContains(path, "paper") || StrContains(path, "poster") {
      eventName = n"lcm_fs_additional_paper_hand_grab";
      if RandRange(0, 2) == 0 {
        eventName = n"lcm_fs_sneakers_paper_land";
      }
    } else {
      variation = RandRange(0, 5);
      switch variation {
        case 0:
          eventName = n"lcm_fs_additional_wood_hollow_hand_grab";
          break;
        case 1:
          eventName = n"lcm_fs_additional_gravel_light_hand_grab";
          break;
        case 2:
          eventName = n"cmn_generic_work_phone_tap_single";
          break;
        case 3:
          eventName = n"lcm_fs_additional_metal_tin_hand_grab";
          break;
        default:
          eventName = n"lcm_fs_additional_metal_grating_hand_grab";
          break;
      }
    }

    GameObject.PlaySoundEvent(player, eventName);
  }

  private final func PlayExamineLootSound(itemRecord: wref<Item_Record>, itemData: wref<gameItemData>) -> Void {
    let eventName: CName = n"inv_loot_generic";
    let player = this.GetPlayer();

    if !IsDefined(player) {
      return;
    }

    if IsDefined(itemRecord as WeaponItem_Record) {
      eventName = n"cmn_generic_metal_foley";
    } else if IsDefined(itemRecord as Clothing_Record) {
      eventName = n"inv_loot_generic";
    } else if IsDefined(itemData) {
      if itemData.HasTag(n"Drink") {
        eventName = n"g_sc_npc_work_grab_can";
      } else if itemData.HasTag(n"Food") {
        eventName = n"cmn_generic_work_food_takeout";
      } else if Equals(itemData.GetItemType(), gamedataItemType.Gen_Junk) {
        if RandRange(0, 2) == 0 {
          eventName = n"lcm_fs_additional_plastic_hand_grab";
        }
      }
    }

    GameObject.PlaySoundEvent(player, eventName);
  }

  private final func BuildInspectionLootActionContext(data: LootData, itemID: ItemID, itemData: wref<gameItemData>) -> ref<ExamineInteractionLootActionContext> {
    let actionName: CName;
    let choice: InteractionChoiceData;
    let context = new ExamineInteractionLootActionContext();
    let i: Int32;
    let isBroken = IsDefined(itemData) && RPGManager.IsItemBroken(itemData);

    context.ownerID = data.ownerId;
    context.itemID = itemID;
    while i < ArraySize(data.choices) {
      choice = data.choices[i];
      if !(Equals(choice.inputAction, n"Choice3")
          && (Equals(choice.localizedName, "Gameplay-Devices-Interactions-Inspect")
            || Equals(choice.localizedName, "Examine")))
        && !ChoiceTypeWrapper.IsType(choice.type, gameinteractionsChoiceType.Inactive)
        && !ChoiceTypeWrapper.IsType(choice.type, gameinteractionsChoiceType.CheckFailed) {
        actionName = this.ResolveInspectionLootChoiceAction(itemID, choice);
        if isBroken && this.ExamineInteractionIsSupportedLootAction(actionName) {
          actionName = n"Disassemble";
          choice.localizedName = "LocKey#6887";
        }
        if this.ExamineInteractionIsSupportedLootAction(actionName) {
          ArrayPush(context.choices, choice);
          ArrayPush(context.actions, actionName);
          ArrayPush(context.sourceChoiceIndices, i);
        }
      }
      i += 1;
    }
    return context;
  }

  private final func ResolveInspectionLootChoiceAction(itemID: ItemID, choice: InteractionChoiceData) -> CName {
    let action: wref<ObjectAction_Record>;
    let actionUI: wref<InteractionBase_Record>;
    let actions: array<wref<ObjectAction_Record>>;
    let i: Int32;
    let itemRecord = TweakDBInterface.GetItemRecord(ItemID.GetTDBID(itemID));

    if IsDefined(itemRecord) {
      itemRecord.ObjectActions(actions);
      if IsDefined(itemRecord.ItemSecondaryAction()) {
        ArrayPush(actions, itemRecord.ItemSecondaryAction());
      }

      while i < ArraySize(actions) {
        action = actions[i];
        if IsDefined(action) {
          actionUI = action.ObjectActionUI();
          if IsDefined(actionUI)
            && Equals(NameToString(actionUI.Caption()), choice.localizedName) {
            return action.ActionName();
          }
        }
        i += 1;
      }
    }

    // Stable (i hope) vanilla loot captions. These cover the engine-owned default choices which are not represented by an ItemAction_Record on the item
    if Equals(choice.localizedName, "LocKey#239") {
      return n"Take";
    }
    if Equals(choice.localizedName, "LocKey#242") {
      return n"EquipItem";
    }
    if Equals(choice.localizedName, "LocKey#49532") {
      return n"Drink";
    }
    if Equals(choice.localizedName, "LocKey#49533") {
      return n"Eat";
    }
    if Equals(choice.localizedName, "LocKey#6887") {
      return n"Disassemble";
    }

    return n"";
  }

  private final func ExamineInteractionIsSupportedLootAction(actionName: CName) -> Bool {
    return Equals(actionName, n"Loot")
      || Equals(actionName, n"Take")
      || Equals(actionName, n"Equip")
      || Equals(actionName, n"EquipItem")
      || Equals(actionName, n"Disassemble")
      || Equals(actionName, n"Consume")
      || Equals(actionName, n"Eat")
      || Equals(actionName, n"Drink")
      || Equals(actionName, n"Learn")
      || Equals(actionName, n"Read");
  }

  public final func RequestInspectionLootAction(context: ref<ExamineInteractionLootActionContext>, choiceIndex: Int32) -> Void {
    let callback: ref<ExamineInteractionLootActionDispatch>;

    if !IsDefined(context) || choiceIndex < 0 || choiceIndex >= ArraySize(context.choices) {
      return;
    }

    callback = ExamineInteractionLootActionDispatch.Create(this, context, choiceIndex);
    GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(callback, 0.06, false);
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Inspection loot action queued after preview restoration: action=\(NameToString(context.choices[choiceIndex].inputAction)) item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(context.itemID)))");
  }

  public final func DispatchInspectionLootAction(context: ref<ExamineInteractionLootActionContext>, choiceIndex: Int32) -> Void {
    let actionName: CName;
    let actionHandled: Bool;
    let audioSystem: ref<AudioSystem>;
    let choiceEvent: ref<InteractionChoiceEvent>;
    let equipRequest: ref<EquipRequest>;
    let itemData: wref<gameItemData>;
    let itemQuantity: Int32;
    let lootAction: LootChoiceActionWrapper;
    let owner: ref<GameObject>;
    let player = this.GetPlayer();
    let selectedChoice: InteractionChoiceData;
    let soundAction: CName;
    let transactionSystem = GameInstance.GetTransactionSystem(GetGameInstance());
    let vanillaAction: CName;

    if !IsDefined(context)
      || choiceIndex < 0
      || choiceIndex >= ArraySize(context.choices)
      || !IsDefined(player) {
      return;
    }

    owner = GameInstance.FindEntityByID(GetGameInstance(), context.ownerID) as GameObject;
    if !IsDefined(owner) {
      FTLog("[ExamineInteraction] Inspection loot action cancelled: the original loot owner is no longer available.");
      return;
    }

    if transactionSystem.GetItemQuantity(owner, context.itemID) <= 0 {
      FTLog("[ExamineInteraction] Inspection loot action cancelled: the examined item is no longer present on its owner.");
      return;
    }

    // Keep source item data alive across the transfer so the sound resolver can still inspect it.
    itemData = transactionSystem.GetItemData(owner, context.itemID);
    selectedChoice = context.choices[choiceIndex];
    if choiceIndex >= ArraySize(context.actions) {
      FTLog("[ExamineInteraction] Inspection loot action cancelled: no authored action was stored for this choice.");
      return;
    }
    if choiceIndex >= ArraySize(context.sourceChoiceIndices) {
      FTLog("[ExamineInteraction] Inspection loot action cancelled: no authored choice index was stored for this choice.");
      return;
    }
    actionName = context.actions[choiceIndex];
    if Equals(actionName, n"") {
      FTLog(s"[ExamineInteraction] Inspection loot action cancelled: the visible choice could not be matched to an item action. inputAction=\(NameToString(selectedChoice.inputAction)) label=\(selectedChoice.localizedName)");
      return;
    }

    if Equals(actionName, n"Equip") {
      actionName = n"EquipItem";
    }

    if Equals(actionName, n"Take") {
      vanillaAction = n"Loot";
    } else {
      vanillaAction = actionName;
    }

    choiceEvent = new InteractionChoiceEvent();
    if !PrepareLootChoiceEvent(choiceEvent, context.itemID, vanillaAction, true, false) {
      FTLog(s"[ExamineInteraction] Vanilla loot interaction could not be prepared: action=\(NameToString(actionName)) item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(context.itemID)))");
      return;
    }
    choiceEvent.hotspot = owner;
    choiceEvent.activator = player;
    choiceEvent.layerData.tag = n"Loot";
    if selectedChoice.isHoldAction {
      choiceEvent.actionType = gameinputActionType.BUTTON_HOLD_COMPLETE;
    } else {
      choiceEvent.actionType = gameinputActionType.BUTTON_RELEASED;
    }
    choiceEvent.choice.caption = selectedChoice.localizedName;
    choiceEvent.choice.captionParts = selectedChoice.captionParts;
    choiceEvent.choice.choiceMetaData.type = selectedChoice.type;
    choiceEvent.choice.choiceMetaData.tweakDBName = NameToString(actionName);
    choiceEvent.choice.choiceMetaData.tweakDBID = TDBID.Create("Interactions." + NameToString(actionName));

    lootAction = LootChoiceActionWrapper.Unwrap(choiceEvent);
    if !LootChoiceActionWrapper.IsValid(lootAction) {
      FTLog(s"[ExamineInteraction] Vanilla loot interaction rejected before dispatch: action=\(NameToString(actionName)) inputAction=\(NameToString(selectedChoice.inputAction)) item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(context.itemID)))");
      return;
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Dispatching vanilla loot interaction: requested=\(NameToString(actionName)) unwrapped=\(NameToString(lootAction.action)) itemMatches=\(Equals(lootAction.itemId, context.itemID)) illegal=\(LootChoiceActionWrapper.IsIllegal(lootAction)) handledByCode=\(LootChoiceActionWrapper.IsHandledByCode(lootAction)) inputAction=\(NameToString(selectedChoice.inputAction))");

    if Equals(actionName, n"Consume")
      || Equals(actionName, n"Eat")
      || Equals(actionName, n"Drink") {
      itemQuantity = transactionSystem.GetItemQuantity(owner, context.itemID);
      actionHandled = transactionSystem.TransferItem(owner, player, context.itemID, itemQuantity);
      if actionHandled {
        if Equals(actionName, n"Consume") {
          ItemActionsHelper.ConsumeItem(player, context.itemID, true);
        } else if Equals(actionName, n"Eat") {
          ItemActionsHelper.EatItem(player, context.itemID, true);
        } else {
          ItemActionsHelper.DrinkItem(player, context.itemID, true);
        }
      }
    } else if Equals(actionName, n"Loot") || Equals(actionName, n"Take") {
      actionHandled = transactionSystem.TransferItem(owner, player, context.itemID, 1);
    } else if Equals(actionName, n"EquipItem") {
      actionHandled = transactionSystem.TransferItem(owner, player, context.itemID, 1);
      if actionHandled {
        equipRequest = new EquipRequest();
        equipRequest.itemID = context.itemID;
        equipRequest.owner = player;
        EquipmentSystem.GetInstance(player).QueueRequest(equipRequest);
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Clothing EquipItem request queued: item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(context.itemID)))");
      }
    } else if Equals(actionName, n"Disassemble") {
      actionHandled = transactionSystem.TransferItem(owner, player, context.itemID, 1);
      if actionHandled {
        ItemActionsHelper.DisassembleItem(player, context.itemID, 1);
      }
    } else if Equals(actionName, n"Learn") {
      actionHandled = transactionSystem.TransferItem(owner, player, context.itemID, 1);
      if actionHandled {
        ItemActionsHelper.LearnItem(player, context.itemID, true);
      }
    } else if Equals(actionName, n"Read") {
      actionHandled = transactionSystem.TransferItem(owner, player, context.itemID, 1);
      if actionHandled {
        ItemActionsHelper.ReadItem(player, context.itemID);
      }
    }

    if !actionHandled {
      FTLog(s"[ExamineInteraction] Inspection loot action failed before success publication: action=\(NameToString(actionName)) item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(context.itemID)))");
      return;
    }

    audioSystem = GameInstance.GetAudioSystem(GetGameInstance());
    soundAction = actionName;
    if Equals(soundAction, n"Take") {
      soundAction = n"Loot";
    }
    audioSystem.PlayItemActionSound(soundAction, itemData);
    if Equals(actionName, n"Disassemble") {
      audioSystem.Play(n"ui_menu_item_disassemble");
    }

    GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(
      ExamineInteractionLootPublishDispatch.Create(this, choiceEvent, context.ownerID, context.itemID, context.sourceChoiceIndices[choiceIndex], 0),
      0.05,
      false
    );
  }

  public final func PublishInspectionLootAction(event: ref<InteractionChoiceEvent>, ownerID: EntityID, itemID: ItemID, sourceChoiceIndex: Int32, attempt: Int32) -> Void {
    let owner = GameInstance.FindEntityByID(GetGameInstance(), ownerID) as GameObject;
    let transactionSystem = GameInstance.GetTransactionSystem(GetGameInstance());

    if !IsDefined(event) || !IsDefined(owner) {
      return;
    }

    if transactionSystem.GetItemQuantity(owner, itemID) > 0 {
      if attempt < 100 {
        GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(
          ExamineInteractionLootPublishDispatch.Create(this, event, ownerID, itemID, sourceChoiceIndex, attempt + 1),
          0.05,
          false
        );
      } else {
        FTLog(s"[ExamineInteraction] Vanilla loot interaction completed without removing the item; the success notification was not published. item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(itemID)))");
      }
      return;
    }

    if !PublishLootChoiceEvent(event, sourceChoiceIndex) {
      FTLog(s"[ExamineInteraction] Vanilla loot interaction succeeded, but its interaction-manager success notification could not be published. item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(itemID)))");
    }
  }

  public final func ProcessLootData(controller: wref<LootingGameController>, out data: LootData) -> Bool {
    let examineChoice: InteractionChoiceData;
    let player = this.GetPlayer();

    this.AttachController(controller);
    this.m_examineInteractionVisible = false;

    if !this.IsEnabled() {
      return this.ExamineInteractionRemoveInjectedChoice(data);
    }

    if data.isActive
      && !data.isLocked
      && ArraySize(data.itemIDs) > 0
      && IsDefined(player)
      && this.ExamineInteractionCanResolveSelectedItem(data, player) {
      this.m_examineInteractionData = data;
      if this.ExamineInteractionHasInjectedChoice(data) {
        this.m_examineInteractionVisible = true;
        return this.ExamineInteractionRefreshInjectedChoice(data);
      } else if !this.ExamineInteractionHasChoice(data) {
        examineChoice.inputAction = n"Choice3";
        examineChoice.rawInputKey = this.m_examineKey;
        examineChoice.isHoldAction = false;
        examineChoice.localizedName = "Gameplay-Devices-Interactions-Inspect";
        ArrayPush(data.choices, examineChoice);
        this.m_examineInteractionVisible = true;
        return true;
      }
    } else if this.ExamineInteractionRemoveInjectedChoice(data) {
      return true;
    }

    return false;
  }

  private final func ExamineInteractionCanResolveSelectedItem(data: LootData, player: wref<PlayerPuppet>) -> Bool {
    let dropObject: ref<gameItemDropObject>;
    let game: GameInstance;
    let index = data.currentIndex;
    let itemID: ItemID;
    let itemObject: ref<ItemObject>;
    let itemData: wref<gameItemData>;
    let itemRecord: wref<Item_Record>;
    let owner: ref<GameObject>;
    let recordID: TweakDBID;
  
    if !IsDefined(player) || ArraySize(data.itemIDs) == 0 {
      return false;
    }
  
    if index < 0 || index >= ArraySize(data.itemIDs) {
      index = 0;
    }
  
    game = player.GetGame();
    itemID = data.itemIDs[index];
    recordID = ItemID.GetTDBID(itemID);
    owner = GameInstance.FindEntityByID(game, data.ownerId) as GameObject;
  
    if IsDefined(owner) {
      itemObject = owner as ItemObject;
      if !IsDefined(itemObject) {
        itemObject = GameInstance.GetTransactionSystem(game).GetItemInSlotByItemID(owner, itemID);
      }
      if !IsDefined(itemObject) {
        dropObject = owner as gameItemDropObject;
        if IsDefined(dropObject) {
          itemObject = dropObject.GetItemObject();
        }
      }
    }
  
    itemRecord = TweakDBInterface.GetItemRecord(recordID);
    if IsDefined(itemObject) {
      if IsDefined(itemRecord as WeaponItem_Record) {
        if IsDefined(owner as gameItemDropObject) {
          return true;
        }
        if IsDefined(owner) {
          itemData = GameInstance.GetTransactionSystem(game).GetItemData(owner, itemID);
        }
        return IsDefined(itemData);
      }
      return true;
    }
    if IsDefined(itemRecord as WeaponItem_Record) && IsDefined(owner) {
      itemData = GameInstance.GetTransactionSystem(game).GetItemData(owner, itemID);
      if IsDefined(itemData) {
        return true;
      }
    }
    if ExamineInteractionClothingFactory.CanResolve(itemRecord, player) && IsDefined(owner) {
      itemData = GameInstance.GetTransactionSystem(game).GetItemData(owner, itemID);
      if IsDefined(itemData) {
        return true;
      }
    }
    if ExamineInteractionGenericItemFactory.CanResolve(itemRecord)
      && IsDefined(owner) {
      itemData = GameInstance.GetTransactionSystem(game).GetItemData(owner, itemID);
      if IsDefined(itemData) {
        return true;
      }
    }
  
    if NotEquals(this.m_examineInteractionLastUnsupported, recordID) {
      this.m_examineInteractionLastUnsupported = recordID;
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Examine prompt suppressed: no live entity or supported visual factory mapping for \(TDBID.ToStringDEBUG(recordID)).");
    }
    return false;
  }
  
  private final func ExamineInteractionHasChoice(data: LootData) -> Bool {
    let i = 0;
    while i < ArraySize(data.choices) {
      if Equals(data.choices[i].inputAction, n"Choice3") {
        return true;
      }
      i += 1;
    }
    return false;
  }
  
  private final func ExamineInteractionHasInjectedChoice(data: LootData) -> Bool {
    let i = 0;
    while i < ArraySize(data.choices) {
      if Equals(data.choices[i].inputAction, n"Choice3")
        && NotEquals(data.choices[i].rawInputKey, EInputKey.IK_None)
        && (Equals(data.choices[i].localizedName, "Gameplay-Devices-Interactions-Inspect")
          || Equals(data.choices[i].localizedName, "Examine")) {
        return true;
      }
      i += 1;
    }
    return false;
  }

  private final func ExamineInteractionRefreshInjectedChoice(out data: LootData) -> Bool {
    let changed: Bool;
    let i = 0;
    while i < ArraySize(data.choices) {
      if Equals(data.choices[i].inputAction, n"Choice3")
        && NotEquals(data.choices[i].rawInputKey, EInputKey.IK_None)
        && (Equals(data.choices[i].localizedName, "Gameplay-Devices-Interactions-Inspect")
          || Equals(data.choices[i].localizedName, "Examine")) {
        if NotEquals(data.choices[i].rawInputKey, this.m_examineKey) {
          data.choices[i].rawInputKey = this.m_examineKey;
          changed = true;
        }
        if NotEquals(data.choices[i].localizedName, "Gameplay-Devices-Interactions-Inspect") {
          data.choices[i].localizedName = "Gameplay-Devices-Interactions-Inspect";
          changed = true;
        }
      }
      i += 1;
    }
    return changed;
  }
  
  private final func ExamineInteractionRemoveInjectedChoice(out data: LootData) -> Bool {
    let i = ArraySize(data.choices) - 1;
    let removed: Bool;
  
    while i >= 0 {
      if Equals(data.choices[i].inputAction, n"Choice3")
        && NotEquals(data.choices[i].rawInputKey, EInputKey.IK_None)
        && (Equals(data.choices[i].localizedName, "Gameplay-Devices-Interactions-Inspect")
          || Equals(data.choices[i].localizedName, "Examine")) {
        ArrayErase(data.choices, i);
        removed = true;
      }
      i -= 1;
    }
    return removed;
  }
  
  private cb func OnExamineInteractionKey(evt: ref<KeyInputEvent>) -> Void {
    let sourceEntity: wref<Entity>;
    let meshAppearance: CName;
    let meshPath: ResRef;
    let sourceNode: wref<worldINodeInstance>;

    if !this.IsEnabled() {
      if Equals(evt.GetKey(), EInputKey.IK_RightMouse)
        && Equals(evt.GetAction(), EInputAction.IACT_Release) {
        this.ExamineInteractionStopPropFocus("RMB released while mod disabled");
      }
      return;
    }
  
    if Equals(evt.GetKey(), EInputKey.IK_RightMouse) {
      if Equals(evt.GetAction(), EInputAction.IACT_Press) {
        this.ExamineInteractionStartPropFocus();
      } else if Equals(evt.GetAction(), EInputAction.IACT_Release) {
        this.ExamineInteractionStopPropFocus("RMB released");
      }
      return;
    }
  
    if this.m_examineInteractionVisible
      && Equals(evt.GetKey(), this.m_examineKey)
      && Equals(evt.GetAction(), EInputAction.IACT_Release) {
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] Examine pressed on world loot.");
      this.ExamineInteractionResolveItemObject();
      return;
    }
  
    if this.m_examinePropPromptVisible
      && Equals(evt.GetKey(), this.m_examineKey)
      && Equals(evt.GetAction(), EInputAction.IACT_Release) {
      sourceEntity = this.m_examineEntityCandidate;
      if IsDefined(sourceEntity)
        && ResRef.IsValid(this.m_examineEntityTemplatePath) {
        FTLog(s"[ExamineInteraction] Examine pressed on curated world entity: class=\(NameToString(sourceEntity.GetClassName())) template=\(ResRef.ToString(this.m_examineEntityTemplatePath)) appearance=\(NameToString(sourceEntity.GetCurrentAppearanceName()))");
        this.ShowWorldEntity(sourceEntity);
        this.ExamineInteractionStopPropFocus("curated entity examine confirmed");
        return;
      }

      sourceNode = AcquireWorldMeshCandidate();
      if !IsDefined(sourceNode) {
        FTLog("[ExamineInteraction] Curated world prop acquisition failed at confirmation; target streamed out.");
        this.ExamineInteractionStopPropFocus("curated prop acquisition failed");
        return;
      }
      meshPath = this.m_examinePropMeshPath;
      meshAppearance = GetWorldNodeAppearance(sourceNode);
      if Equals(meshAppearance, n"") {
        meshAppearance = n"default";
      }
      FTLog(s"[ExamineInteraction] Examine pressed on curated world prop: mesh=\(ResRef.ToString(meshPath)) appearance=\(NameToString(meshAppearance)) grouped=\(IsWorldNodeGrouped(sourceNode)) selection=\(GetWorldNodeSelectionIndex(sourceNode))/\(GetWorldNodeSelectionCount(sourceNode))");
      this.PlayExamineWorldMeshSound(meshPath);
      ExamineInteractionPopup.ShowWorldMesh(
        sourceNode,
        meshPath,
        meshAppearance,
        this.m_controller
      );
      this.ExamineInteractionStopPropFocus("curated prop examine confirmed");
      return;
    }

    if Equals(evt.GetKey(), this.m_examineKey)
      && Equals(evt.GetAction(), EInputAction.IACT_Release) {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] PROP CONFIRM UNHANDLED: focusHeld=\(this.m_examinePropFocusHeld) promptVisible=\(this.m_examinePropPromptVisible) focusPolls=\(this.m_examinePropFocusPolls) stablePolls=\(this.m_examinePropStablePolls) missPolls=\(this.m_examinePropMissPolls) entity=\(IsDefined(this.m_examineEntityCandidate)) mesh=\(ResRef.ToString(this.m_examinePropMeshPath))");
    }
  }
  
  private final func ExamineInteractionStartPropFocus() -> Void {
    let player = this.GetPlayer();
    let weapon: ref<WeaponObject>;
  
    if !this.IsEnabled() {
      return;
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] PROP FOCUS INPUT: RMB press received; lootVisible=\(this.m_examineInteractionVisible) playerDefined=\(IsDefined(player))");
  
    if this.m_examineInteractionVisible || !IsDefined(player) {
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] PROP FOCUS BLOCKED: loot UI is active or player owner is unavailable.");
      return;
    }
  
    weapon = GameObject.GetActiveWeapon(player);
    if IsDefined(weapon) && !WeaponObject.IsFists(weapon.GetItemID()) {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] PROP FOCUS BLOCKED: active non-fists weapon=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(weapon.GetItemID())))");
      return;
    }
  
    this.m_examinePropFocusHeld = true;
    this.m_examinePropDiagnosticLogged = false;
    this.m_examinePropFocusGeneration += 1u;
    this.m_examinePropFocusPolls = 0;
    this.m_examinePropStablePolls = 0;
    this.m_examinePropMissPolls = 0;
    GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(
      ExamineInteractionPropFocusPoll.Create(this, this.m_examinePropFocusGeneration),
      0.10,
      false
    );
  }
  
  private final func ExamineInteractionStopPropFocus(reason: String) -> Void {
    if this.m_examinePropFocusHeld
      || this.m_examinePropPromptVisible
      || this.m_examinePropFocusPolls > 0 {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] PROP FOCUS STOP: reason=\(reason) focusHeld=\(this.m_examinePropFocusHeld) promptVisible=\(this.m_examinePropPromptVisible) focusPolls=\(this.m_examinePropFocusPolls) stablePolls=\(this.m_examinePropStablePolls) missPolls=\(this.m_examinePropMissPolls) entity=\(IsDefined(this.m_examineEntityCandidate)) mesh=\(ResRef.ToString(this.m_examinePropMeshPath))");
    }
    this.m_examinePropFocusHeld = false;
    this.m_examinePropDiagnosticLogged = false;
    this.m_examinePropFocusGeneration += 1u;
    this.m_examinePropFocusPolls = 0;
    this.m_examinePropStablePolls = 0;
    this.m_examinePropMissPolls = 0;
    this.m_examinePropCandidate = null;
    this.m_examinePropCandidateID = Cast<EntityID>(GlobalNodeID.GetRoot());
    this.m_examineEntityCandidate = null;
    this.m_examineEntityTemplatePath = r"";
    this.m_examinePropMeshPath = r"";
    this.m_examinePropMeshAppearance = n"";
    this.ExamineInteractionSetPropHint(false);
  }
  
  public final func ExamineInteractionPollPropFocus(generation: Uint32) -> Void {
    let aimForward: Vector4;
    let boundsAttempts: Int32;
    let boundsMeshPath: ResRef;
    let endPosition: Vector4;
    let entityCandidate: ref<Entity>;
    let entityTemplatePath: ResRef;
    let entityAttempts: Int32;
    let entityVisibilityRejects: Int32;
    let excludedEntities: array<wref<Entity>>;
    let excludedBoundsPaths: array<ResRef>;
    let hitObject: ref<ISerializable>;
    let hit: Bool;
    let meshNode: ref<worldMeshNode>;
    let meshPath: ResRef;
    let nodeInstance: ref<worldINodeInstance>;
    let player = this.GetPlayer();
    let startPosition: Vector4;
    let lookedAtObject: ref<GameObject>;
    let trace: TraceResult;
  
    if generation != this.m_examinePropFocusGeneration
      || !this.m_examinePropFocusHeld
      || !IsDefined(player) {
      return;
    }

    this.m_examinePropFocusPolls += 1;
  
    if !this.m_examineInteractionVisible {
      GameInstance.GetTargetingSystem(player.GetGame()).GetCrosshairData(
        player,
        startPosition,
        aimForward
      );

      // Prefer a real authored entity over its individual mesh components. This is what apartment memorabilia and stash display weapons need: cloning the full template preserves authored multi-mesh composition and rigging
      lookedAtObject = GameInstance.GetTargetingSystem(player.GetGame())
        .GetLookAtObject(player, true, true);
      entityCandidate = lookedAtObject as Entity;

      if !IsDefined(entityCandidate) {
        endPosition = startPosition + aimForward * 3.0;
        hit = GameInstance.GetSpatialQueriesSystem(player.GetGame())
          .SyncRaycastByCollisionGroup(startPosition, endPosition, n"Dynamic", trace, true, false);
        if hit {
          hitObject = TraceResult.GetHitObject(trace);
          entityCandidate = hitObject as Entity;
        }
      }

      if IsDefined(entityCandidate) {
        entityTemplatePath = entityCandidate.GetTemplatePath();
        if !this.ExamineInteractionIsCuratedEntity(entityTemplatePath) {
          entityCandidate = null;
          entityTemplatePath = r"";
        }
      }

      // Passive apartment memorabilia and stash displays are streamed worldEntityNodes. They are not targeting GameObjects and frequently have no collision, so select their live entities through the native transformed-bounds registry before falling back to mesh-only props
      while !IsDefined(entityCandidate) && entityAttempts < 16 {
        entityCandidate = FindWorldEntity(
          startPosition,
          aimForward,
          3.0,
          excludedEntities
        );
        if !IsDefined(entityCandidate) {
          break;
        }

        entityTemplatePath = entityCandidate.GetTemplatePath();
        if this.ExamineInteractionIsCuratedEntity(entityTemplatePath)
          && this.ExamineInteractionHasWorldEntityLineOfSight(player.GetGame(), startPosition, entityCandidate) {
          break;
        }
        if this.ExamineInteractionIsCuratedEntity(entityTemplatePath) {
          entityVisibilityRejects += 1;
        }

        ArrayPush(excludedEntities, entityCandidate);
        entityCandidate = null;
        entityTemplatePath = r"";
        entityAttempts += 1;
      }
  
      while !IsDefined(entityCandidate) && boundsAttempts < 16 {
        boundsMeshPath = FindWorldMeshPath(
          startPosition,
          aimForward,
          3.0,
          excludedBoundsPaths
        );
        if !ResRef.IsValid(boundsMeshPath) {
          break;
        }
  
        if this.ExamineInteractionIsCuratedProp(boundsMeshPath) {
          meshPath = boundsMeshPath;
          break;
        }
        ArrayPush(excludedBoundsPaths, boundsMeshPath);
        boundsAttempts += 1;
      }
  
      // Keep the Codeware collision result as a fallback for curated meshes that do have collision. Thin decorative meshes normally resolve through the native transformed-bounds query above
      if !IsDefined(entityCandidate) && !IsDefined(nodeInstance) {
        endPosition = startPosition + aimForward * 3.0;
        hit = GameInstance.GetSpatialQueriesSystem(player.GetGame())
          .SyncRaycastByCollisionGroup(startPosition, endPosition, n"Static", trace, true, false);
        if hit {
          hitObject = TraceResult.GetHitObject(trace);
          nodeInstance = hitObject as worldINodeInstance;
          if IsDefined(nodeInstance) {
            meshNode = nodeInstance.GetNode() as worldMeshNode;
          }
          if IsDefined(meshNode) {
            meshPath = ResourceAsyncRef.GetPath(meshNode.mesh);
          }
        }
      }
    }
  
    if !this.m_examinePropDiagnosticLogged {
      this.m_examinePropDiagnosticLogged = true;
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] PROP TARGET PROBE: entity=\(IsDefined(entityCandidate)) entityTemplate=\(ResRef.ToString(entityTemplatePath)) entityAttempts=\(entityAttempts) entityVisibilityRejects=\(entityVisibilityRejects) boundsAttempts=\(boundsAttempts) boundsPath=\(ResRef.ToString(boundsMeshPath)) physicsHit=\(hit) hitObject=\(IsDefined(hitObject)) mesh=\(ResRef.ToString(meshPath)) curated=\(this.ExamineInteractionIsCuratedProp(meshPath))");
    }
  
    if IsDefined(entityCandidate)
      && ResRef.IsValid(entityTemplatePath) {
      if IsDefined(this.m_examineEntityCandidate)
        && this.m_examineEntityCandidate.GetEntityID() == entityCandidate.GetEntityID() {
        this.m_examinePropStablePolls += 1;
      } else {
        this.m_examineEntityCandidate = entityCandidate;
        this.m_examineEntityTemplatePath = entityTemplatePath;
        this.m_examinePropMeshPath = r"";
        this.m_examinePropStablePolls = 1;
        this.m_examinePropMissPolls = 0;
        this.ExamineInteractionSetPropHint(false);
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Curated entity focus candidate: class=\(NameToString(entityCandidate.GetClassName())) template=\(ResRef.ToString(entityTemplatePath))");
      }

      this.m_examinePropMissPolls = 0;
      if this.m_examinePropStablePolls >= 3 {
        this.ExamineInteractionSetPropHint(true);
      }
    } else if ResRef.IsValid(meshPath)
      && this.ExamineInteractionIsCuratedProp(meshPath) {
      if ResRef.IsValid(this.m_examinePropMeshPath)
        && Equals(meshPath, this.m_examinePropMeshPath) {
        this.m_examinePropStablePolls += 1;
      } else {
        this.m_examineEntityCandidate = null;
        this.m_examineEntityTemplatePath = r"";
        this.m_examinePropMeshPath = meshPath;
        this.m_examinePropMeshAppearance = n"default";
        this.m_examinePropStablePolls = 1;
        this.m_examinePropMissPolls = 0;
        this.ExamineInteractionSetPropHint(false);
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Curated prop focus candidate path: mesh=\(ResRef.ToString(meshPath))");
      }
  
      this.m_examinePropMissPolls = 0;
      if this.m_examinePropStablePolls >= 3 {
        this.ExamineInteractionSetPropHint(true);
      }
    } else {
      this.m_examinePropMissPolls += 1;
      if this.m_examinePropMissPolls >= 2 {
        this.m_examineEntityCandidate = null;
        this.m_examineEntityTemplatePath = r"";
        this.m_examinePropMeshPath = r"";
        this.m_examinePropStablePolls = 0;
        this.ExamineInteractionSetPropHint(false);
      }
    }

    if this.m_examinePropFocusPolls % 10 == 0 {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] PROP FOCUS HEARTBEAT: generation=\(generation) focusPolls=\(this.m_examinePropFocusPolls) focusHeld=\(this.m_examinePropFocusHeld) promptVisible=\(this.m_examinePropPromptVisible) stablePolls=\(this.m_examinePropStablePolls) missPolls=\(this.m_examinePropMissPolls) entity=\(IsDefined(this.m_examineEntityCandidate)) mesh=\(ResRef.ToString(this.m_examinePropMeshPath))");
    }
  
    GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(
      ExamineInteractionPropFocusPoll.Create(this, generation),
      0.10,
      false
    );
  }

  private final func ExamineInteractionHasWorldEntityLineOfSight(
    game: GameInstance,
    startPosition: Vector4,
    candidate: wref<Entity>
  ) -> Bool {
    let candidateDistance: Float;
    let candidateDirection: Vector4;
    let endPosition: Vector4;
    let trace: TraceResult;

    if !IsDefined(candidate) {
      return false;
    }

    candidateDirection = candidate.GetWorldPosition() - startPosition;
    candidateDistance = Vector4.Length(candidateDirection);
    if candidateDistance <= 0.05 || candidateDistance > 3.05 {
      return false;
    }

    // worldEntityNode bounds can extend through nearby walls or well beyond the entity's authored origin. Confirm that static geometry does not obstruct the route to collisionless entity candidates. Stop just short of the origin so a poster, frame, or stash weapon mounted on a wall does not reject itself because its authored pivot touches the backing surface
    endPosition = startPosition
      + Vector4.Normalize(candidateDirection) * MaxF(candidateDistance - 0.05, 0.01);
    return !GameInstance.GetSpatialQueriesSystem(game)
      .SyncRaycastByCollisionGroup(startPosition, endPosition, n"Static", trace, true, false);
  }

  private final func ExamineInteractionIsCuratedEntity(templatePath: ResRef) -> Bool {
    let path = ResRef.ToString(templatePath);

    // Apartment memorabilia and authored stash displays are deliberately exact or directory-scoped. Broad quest/entity prefixes would make RMB focus noisy and could clone scripted quest actors or devices accidentally
    return Equals(path, "base\\quest\\main_quests\\prologue\\q001\\entities\\q001_waving_cat.ent")
      || Equals(path, "ep1\\quest\\main_quests\\q302\\entities\\q302_chimera_core\\q302_chimera_shell_memorabilia.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq000\\entities\\mq000_gwent_plushie.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq000\\entities\\mq000_statue_02.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq001\\entities\\mq001_scorpion_ultimate_final.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq000\\entities\\mq000_statue_01.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq000\\entities\\mq000_poster_01.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq000\\entities\\mq000_poster_02.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq000\\entities\\mq000_poster_03.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq025\\entities\\mq025_v_trophy.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq029\\entities\\mq029_ent_photo.ent")
      || Equals(path, "base\\quest\\minor_quests\\mq029\\entities\\mq029_ent_photo_v2.ent")
      || Equals(path, "base\\quest\\side_quests\\sq006\\entities\\sq006_family_photos.ent")
      || Equals(path, "base\\quest\\side_quests\\sq006\\entities\\sq006_mayor_photo.ent")
      || Equals(path, "base\\quest\\side_quests\\sq006\\entities\\sq006_family_photos_daughter.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_vinyl_2.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_guitar_fluff_2.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_guitar_fluff_4.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_vinyl_1.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_guitar_fluff_3.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_vinyl_3.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_vinyl_4.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_kerry_guitar.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_bass_guitar.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_guitar.ent")
      || Equals(path, "base\\quest\\side_quests\\sq011\\entities\\sq011_guitar_fluff_1.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_pen.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_vodka.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_belt.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_machete.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_keycard_door.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_photo_misty.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_photo_jackie.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_poster.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_book.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_guns.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_ball.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_package.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_drink.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_toolbox.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_jackies_urn.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_tequila_bottle.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_poster_gym.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_tequila_glass.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_victors_gloves.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_beer_bottles.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_jackies_gun.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_photo_mama_welles.ent")
      || Equals(path, "base\\quest\\side_quests\\sq018\\entities\\sq018_bike_key.ent")
      || Equals(path, "base\\quest\\side_quests\\sq021\\entities\\sq021_poster.ent")
      || Equals(path, "base\\quest\\side_quests\\sq021\\entities\\sq021_lab_drawing.ent")
      || Equals(path, "base\\quest\\side_quests\\sq021\\entities\\sq021_lab_drawing_3.ent")
      || Equals(path, "base\\quest\\side_quests\\sq021\\entities\\sq021_lab_drawing_2.ent")
      || Equals(path, "base\\open_world\\street_stories\\heywood\\glenn\\sts_hey_gle_03\\entitites\\sts_hey_gle_03_drink.ent")
      || Equals(path, "base\\open_world\\street_stories\\heywood\\glenn\\sts_hey_gle_03\\entitites\\sts_hey_gle_03_poster_door.ent")
      || Equals(path, "base\\open_world\\street_stories\\heywood\\glenn\\sts_hey_gle_03\\entitites\\sts_hey_gle_03_poster_3.ent")
      || Equals(path, "base\\open_world\\street_stories\\heywood\\glenn\\sts_hey_gle_03\\entitites\\sts_hey_gle_03_poster_2.ent")
      || Equals(path, "base\\open_world\\street_stories\\heywood\\glenn\\sts_hey_gle_03\\entitites\\sts_hey_gle_03_poster_1.ent")
      || Equals(path, "base\\open_world\\street_stories\\heywood\\glenn\\sts_hey_gle_03\\entitites\\sts_hey_gle_03_photo.ent")
      || Equals(path, "base\\open_world\\street_stories\\heywood\\glenn\\sts_hey_gle_03\\entitites\\sts_hey_gle_03_kerry_guitar.entw")
      || StrBeginsWith(path, "base\\quest\\minor_quests\\mq000\\entities\\stash_weapons\\");
  }
  
  private final func ExamineInteractionIsCuratedProp(meshPath: ResRef) -> Bool {
    let path = ResRef.ToString(meshPath);
    if Equals(path, "base\\environment\\decoration\\misc\\painting\\rich_painting\\rich_painting_frame_a.mesh")
      || Equals(path, "base\\environment\\decoration\\misc\\painting\\rich_painting\\rich_painting_frame_b.mesh")
      || Equals(path, "base\\environment\\decoration\\misc\\painting\\rich_painting\\rich_painting_frame_c.mesh")
      || Equals(path, "base\\environment\\decoration\\misc\\painting\\rich_painting\\rich_painting_frame_d.mesh")
      || Equals(path, "base\\environment\\decoration\\misc\\painting\\rich_painting\\rich_painting_frame_e.mesh")
      || Equals(path, "base\\environment\\decoration\\misc\\painting\\rich_painting\\rich_painting_frame_f.mesh") {
      return false;
    }
    return StrBeginsWith(path, "ep1\\environment\\decoration\\advertising\\posters\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\advertising\\posters\\")
      || StrBeginsWith(path, "base\\characters\\garment\\gang_valentino\\item\\i1_090_full__jewlery\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\apparel\\accessories\\lighter\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\apparel\\cosmetics\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\containers\\bottles")
      || StrBeginsWith(path, "base\\environment\\decoration\\containers\\buckets")
      || StrBeginsWith(path, "base\\environment\\decoration\\containers\\bags")
      || StrBeginsWith(path, "base\\environment\\decoration\\containers\\cases")
      || StrBeginsWith(path, "base\\environment\\decoration\\containers\\exotic\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\containers\\packaging")
      || StrBeginsWith(path, "base\\environment\\decoration\\containers\\vases\\rich_vase_small\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\dining_accessories")
      || StrBeginsWith(path, "base\\environment\\decoration\\electronics\\appliances\\coffee_machine")
      || StrBeginsWith(path, "base\\environment\\decoration\\electronics\\appliances\\kitchen_appliance")
      || StrBeginsWith(path, "base\\environment\\decoration\\electronics\\audio\\record_player")
      || StrBeginsWith(path, "base\\environment\\decoration\\electronics\\audio\\jukebox")
      || StrBeginsWith(path, "base\\environment\\decoration\\electronics\\devices\\tablet")
      || StrBeginsWith(path, "base\\environment\\decoration\\electronics\\devices\\speaker")
      || StrBeginsWith(path, "base\\environment\\decoration\\electronics\\entertainment\\poor_home_electronic_small")
      || StrBeginsWith(path, "base\\environment\\decoration\\electronics\\hardware\\keyboard")
      || StrBeginsWith(path, "base\\environment\\decoration\\electronics\\hardware\\id_card_chip")
      || Equals(path, "base\\environment\\decoration\\electronics\\hardware\\server_entropy\\server_entropy_a_harddrive.mesh")
      || StrBeginsWith(path, "base\\environment\\decoration\\food\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\garbage\\trash\\cardboard_homeless_sign\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\garbage\\trash\\foil_bag\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\garbage\\trash\\garbage_bag_transparent\\")
      || (StrBeginsWith(path, "base\\environment\\decoration\\garbage\\trash\\garbage_bag") && StrFindFirst(path, "pile") < 0)
      || StrBeginsWith(path, "base\\environment\\decoration\\garbage\\trash\\trash_packaging\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\medical\\accessories\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\money")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\music")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\office")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\painting")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\paper")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\sculptures\\chinese_sculpture_small\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\sculptures\\colorful_mask\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\sculptures\\colorful_skull")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\shops\\cellphone\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\shops\\cyber_arms\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\shops\\int_medical_deco\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\shops\\laptop_bag\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\shops\\medical_deco\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\shops\\price_tags\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\tarot\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\various\\bubble_gum")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\various\\flare")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\various\\funeral_item")
      || StrBeginsWith(path, "base\\environment\\decoration\\misc\\various\\hand_fan")
      || StrBeginsWith(path, "base\\environment\\decoration\\recreation\\games\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\recreation\\drugs\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\recreation\\smoking\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\recreation\\sports\\ball")
      || StrBeginsWith(path, "base\\environment\\decoration\\recreation\\sports\\billiard_stick")
      || StrBeginsWith(path, "base\\environment\\decoration\\recreation\\sports\\cricket_bat")
      || Equals(path, "base\\environment\\decoration\\recreation\\sports\\gym_accessories\\gym_accessories_b_boxing_gloves.mesh")
      || Equals(path, "base\\environment\\decoration\\recreation\\sports\\gym_weights\\gym_weights_c_dumbbell_small.mesh")
      || Equals(path, "base\\environment\\decoration\\recreation\\sports\\gym_weights\\gym_weights_h.mesh")
      || StrBeginsWith(path, "base\\environment\\decoration\\recreation\\sports\\trophies")
      || StrBeginsWith(path, "base\\environment\\decoration\\recreation\\sports\\surf_board")
      || StrBeginsWith(path, "base\\environment\\decoration\\sanitation\\cleaning\\bottle_disinfectant")
      || StrBeginsWith(path, "base\\environment\\decoration\\textiles\\bathwear")
      || StrBeginsWith(path, "base\\environment\\decoration\\textiles\\bedding\\bed_pillow")
      || StrBeginsWith(path, "base\\environment\\decoration\\textiles\\bedding\\blanket")
      || StrBeginsWith(path, "base\\environment\\decoration\\textiles\\cleaning\\cleaning_rag")
      || StrBeginsWith(path, "base\\environment\\decoration\\textiles\\clothes\\laundry\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\textiles\\clothes\\clothes_folded")
      || StrBeginsWith(path, "base\\environment\\decoration\\textiles\\clothes\\clothes_scattered\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\tools\\office")
      || StrBeginsWith(path, "base\\environment\\decoration\\tools\\cleaning")
      || StrBeginsWith(path, "base\\environment\\decoration\\tools\\workshop")
      || StrBeginsWith(path, "base\\environment\\decoration\\toys\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\unique\\quest\\sq018\\sq018_jackie_pinup_poster\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\unique\\quest\\sq026\\sq026_diving_suit_box_a\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\lighting\\candles\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\lighting\\industrial\\glow_stick")
      || StrBeginsWith(path, "base\\environment\\decoration\\lighting\\lanterns\\")
      || StrBeginsWith(path, "base\\environment\\decoration\\lighting\\residential\\poor_desk_lamp")
      || StrBeginsWith(path, "ep1\\environment\\decoration\\containers\\packaging\\cardboard_box")
      || StrBeginsWith(path, "ep1\\environment\\decoration\\lighting\\candles\\candle")
      || StrBeginsWith(path, "ep1\\environment\\decoration\\misc\\painting")
      || StrBeginsWith(path, "ep1\\environment\\decoration\\recreation\\sports\\trophies\\")
      || StrBeginsWith(path, "ep1\\environment\\decoration\\recreation\\games\\")
      || StrBeginsWith(path, "ep1\\environment\\decoration\\toys\\");
  }
  
  private final func ExamineInteractionSetPropHint(show: Bool) -> Void {
    if Equals(show, this.m_examinePropPromptVisible) {
      if IsDefined(this.m_controller) {
        this.m_controller.ExamineInteractionSetWorldPropPrompt(show, this.m_examineKey);
      }
      return;
    }
  
    this.m_examinePropPromptVisible = show;
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Curated prop Examine hint changed: show=\(show) stablePolls=\(this.m_examinePropStablePolls) candidatePath=\(ResRef.IsValid(this.m_examinePropMeshPath)) mesh=\(ResRef.ToString(this.m_examinePropMeshPath))");
    if IsDefined(this.m_controller) {
      this.m_controller.ExamineInteractionSetWorldPropPrompt(show, this.m_examineKey);
    }
  }
  
  private final func ExamineInteractionResolveItemObject() -> Void {
    let components: array<ref<IComponent>>;
    let data = this.m_examineInteractionData;
    let dropObject: ref<gameItemDropObject>;
    let game: GameInstance;
    let i: Int32;
    let index = data.currentIndex;
    let itemID: ItemID;
    let itemData: wref<gameItemData>;
    let itemObject: ref<ItemObject>;
    let itemRecord: wref<Item_Record>;
    let lookedAtObject: ref<GameObject>;
    let owner: ref<GameObject>;
    let player = this.GetPlayer();
    let resolvedBy = "none";
  
    if !IsDefined(player) || ArraySize(data.itemIDs) == 0 {
      FTLog("[ExamineInteraction] Resolver failed: player or loot item data is unavailable.");
      return;
    }
  
    if index < 0 || index >= ArraySize(data.itemIDs) {
      index = 0;
    }
  
    game = player.GetGame();
    itemID = data.itemIDs[index];
    itemRecord = TweakDBInterface.GetItemRecord(ItemID.GetTDBID(itemID));
    owner = GameInstance.FindEntityByID(game, data.ownerId) as GameObject;
    if IsDefined(owner) {
      itemData = GameInstance.GetTransactionSystem(game).GetItemData(owner, itemID);
    }
  
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Selected item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(itemID))) index=\(index) owner=\(EntityID.ToDebugString(data.ownerId))");
    if IsDefined(itemRecord) {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Item record entityName=\(NameToString(itemRecord.EntityName())) appearanceName=\(NameToString(itemRecord.AppearanceName()))");
    }
    if IsDefined(owner) {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Loot owner class=\(NameToString(owner.GetClassName())) template=\(ResRef.ToString(owner.GetTemplatePath())) appearance=\(NameToString(owner.GetCurrentAppearanceName()))");
      itemObject = GameInstance.GetTransactionSystem(game).GetItemInSlotByItemID(owner, itemID);
      if IsDefined(itemObject) {
        resolvedBy = "TransactionSystem.GetItemInSlotByItemID";
      }
  
      if !IsDefined(itemObject) {
        dropObject = owner as gameItemDropObject;
        if IsDefined(dropObject) {
          itemObject = dropObject.GetItemObject();
          if IsDefined(itemObject) {
            resolvedBy = "gameItemDropObject.GetItemObject";
          }
        }
      }
    }
  
    if !IsDefined(itemObject) {
      lookedAtObject = GameInstance.GetTargetingSystem(game).GetLookAtObject(player, true, true);
      itemObject = lookedAtObject as ItemObject;
      if IsDefined(itemObject) && itemObject.GetItemID() == itemID {
        resolvedBy = "TargetingSystem.GetLookAtObject";
      } else {
        itemObject = null;
      }
    }
  
    if IsDefined(itemRecord as WeaponItem_Record) {
      if IsDefined(itemObject) {
        if !IsDefined(itemData) {
          itemData = itemObject.GetItemData();
        }
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] WEAPON ITEM-OBJECT ACCESSOR PROBE: defined=true resolvedBy=\(resolvedBy) class=\(NameToString(itemObject.GetClassName())) id=\(EntityID.ToDebugString(itemObject.GetEntityID())) template=\(ResRef.ToString(itemObject.GetTemplatePath())) appearance=\(NameToString(itemObject.GetCurrentAppearanceName()))");
      } else if IsDefined(owner) {
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] WEAPON ITEM-OBJECT ACCESSOR PROBE: defined=false ownerClass=\(NameToString(owner.GetClassName()))");
      } else {
        ExamineInteractionLog.Diagnostic("[ExamineInteraction] WEAPON ITEM-OBJECT ACCESSOR PROBE: defined=false ownerClass=undefined");
      }
  
      dropObject = owner as gameItemDropObject;
      if IsDefined(itemObject) && IsDefined(dropObject) {
        ExamineInteractionLog.Diagnostic("[ExamineInteraction] Using the existing engine-assembled ground weapon for inspection.");
        this.PlayExamineLootSound(itemRecord, itemData);
        ExamineInteractionPopup.ShowBorrowedWorldWeapon(
          itemObject,
          dropObject,
          itemID,
          itemData,
          player,
          this.m_controller,
          this.BuildInspectionLootActionContext(data, itemID, itemData)
        );
        return;
      }

      if !IsDefined(itemData) && IsDefined(owner) {
        itemData = GameInstance.GetTransactionSystem(game).GetItemData(owner, itemID);
      }
      if !IsDefined(itemData) || !IsDefined(owner) {
        FTLog("[ExamineInteraction] Weapon inspection suppressed: exact source gameItemData is unavailable.");
        return;
      }
      if IsDefined(this.m_examineItemPreviewFactory)
        && this.m_examineItemPreviewFactory.IsActive() {
        FTLog("[ExamineInteraction] Weapon inspection ignored while the previous asynchronous preview is still active.");
        return;
      }

      this.m_examineItemPreviewFactory = new ExamineInteractionWeaponPreviewFactory();
      this.PlayExamineLootSound(itemRecord, itemData);
      this.m_examineItemPreviewFactory.Begin(
        itemID,
        itemData,
        itemObject,
        owner,
        player,
        this.m_controller,
        this.BuildInspectionLootActionContext(data, itemID, itemData),
        true
      );
      return;
    }
  
    if !IsDefined(itemObject) {
      if ExamineInteractionClothingFactory.CanResolve(itemRecord, player) {
        this.ExamineInteractionLoadClothingFactory(itemRecord, itemID, itemData, player);
        return;
      }
      if ExamineInteractionGenericItemFactory.CanResolve(itemRecord) {
        this.ExamineInteractionLoadGenericItemFactory(itemRecord, itemID, itemData, owner, player);
        return;
      }
  
      FTLog("[ExamineInteraction] No live ItemObject or supported item factory visual resolved.");
      return;
    }
  
    FTLog(s"[ExamineInteraction] Resolved via \(resolvedBy): class=\(NameToString(itemObject.GetClassName())) id=\(EntityID.ToDebugString(itemObject.GetEntityID())) template=\(ResRef.ToString(itemObject.GetTemplatePath())) appearance=\(NameToString(itemObject.GetCurrentAppearanceName()))");
  
    if ExamineInteractionLog.DiagnosticsEnabled() {
      components = itemObject.GetComponents();
      i = 0;
      while i < ArraySize(components) {
        FTLog(s"[ExamineInteraction] Item component[\(i)] class=\(NameToString(components[i].GetClassName())) name=\(NameToString(components[i].GetName()))");
        i += 1;
      }
    }
  
    if !IsDefined(itemData) {
      itemData = itemObject.GetItemData();
    }
    this.PlayExamineLootSound(itemRecord, itemData);
    ExamineInteractionPopup.Show(
      itemObject,
      itemData,
      player,
      this.m_controller,
      this.BuildInspectionLootActionContext(data, itemID, itemData)
    );
  }

  private final func ExamineInteractionLoadGenericItemFactory(itemRecord: wref<Item_Record>, itemID: ItemID, itemData: wref<gameItemData>, owner: wref<GameObject>, player: wref<PlayerPuppet>) -> Void {
    let templatePath: ResRef;
    let token: ref<ResourceToken>;

    if !IsDefined(itemRecord)
      || !IsDefined(itemData)
      || !IsDefined(player) {
      return;
    }

    templatePath = ExamineInteractionGenericItemFactory.ResolveTemplate(itemRecord.EntityName());
    token = GameInstance.GetResourceDepot().LoadResource(templatePath);
    if !IsDefined(token) {
      FTLog(s"[ExamineInteraction] Generic item factory load failed: entityName=\(NameToString(itemRecord.EntityName())) template=\(ResRef.ToString(templatePath))");
      return;
    }

    this.PlayExamineLootSound(itemRecord, itemData);
    this.m_examineGenericToken = token;
    this.m_examineGenericTemplatePath = templatePath;
    this.m_examineGenericAppearance = itemRecord.AppearanceName();
    this.m_examineGenericEntityName = itemRecord.EntityName();
    this.m_examineGenericItemID = itemID;
    this.m_examineGenericItemData = itemData;
    if IsDefined(owner) {
      this.m_examineGenericQuantity = GameInstance.GetTransactionSystem(player.GetGame()).GetItemQuantity(owner, itemID);
    } else {
      this.m_examineGenericQuantity = 0;
    }
    if itemData.HasTag(n"Currency") {
      // Vanilla's single Take choice collects the entire currency stack. The inspection executor intentionally operates on one ordinary item, so do not offer a misleading partial-stack Take action for money
      this.m_examineGenericActionContext = null;
    } else {
      this.m_examineGenericActionContext = this.BuildInspectionLootActionContext(this.m_examineInteractionData, itemID, itemData);
    }

    if token.IsLoaded() {
      this.ExamineInteractionCompleteGenericItemFactory(token);
    } else if token.IsFailed() {
      FTLog(s"[ExamineInteraction] Generic item factory resource failed immediately: template=\(ResRef.ToString(templatePath))");
    } else {
      token.RegisterCallback(this, n"OnExamineInteractionGenericItemFactoryReady");
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Generic item factory resource requested: entityName=\(NameToString(itemRecord.EntityName())) template=\(ResRef.ToString(templatePath)) appearance=\(NameToString(itemRecord.AppearanceName()))");
    }
  }

  private cb func OnExamineInteractionGenericItemFactoryReady(token: ref<ResourceToken>) -> Void {
    this.ExamineInteractionCompleteGenericItemFactory(token);
  }

  private final func ExamineInteractionCompleteGenericItemFactory(token: ref<ResourceToken>) -> Void {
    let appearanceName: CName;
    let template: ref<entEntityTemplate>;

    if !IsDefined(token)
      || !Equals(token.GetPath(), this.m_examineGenericTemplatePath)
      || token.IsFailed()
      || !token.IsLoaded() {
      FTLog("[ExamineInteraction] Generic item factory completion ignored: resource token is stale or failed.");
      return;
    }

    template = token.GetResource() as entEntityTemplate;
    appearanceName = ExamineInteractionGenericItemFactory.ResolveAppearance(
      template,
      this.m_examineGenericAppearance
    );

    if Equals(appearanceName, n"") {
      FTLog(s"[ExamineInteraction] Generic item preview suppressed: factory has no requested or default appearance. entityName=\(NameToString(this.m_examineGenericEntityName)) requested=\(NameToString(this.m_examineGenericAppearance)) template=\(ResRef.ToString(this.m_examineGenericTemplatePath))");
      this.m_examineGenericToken = null;
      this.m_examineGenericItemData = null;
      this.m_examineGenericQuantity = 0;
      this.m_examineGenericActionContext = null;
      return;
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Resolved generic item from authored factory appearance: entityName=\(NameToString(this.m_examineGenericEntityName)) template=\(ResRef.ToString(this.m_examineGenericTemplatePath)) appearance=\(NameToString(appearanceName))");
    ExamineInteractionPopup.ShowResolved(
      this.m_examineGenericTemplatePath,
      appearanceName,
      this.m_examineGenericItemID,
      this.m_examineGenericItemData,
      this.GetPlayer(),
      this.m_controller,
      this.m_examineGenericActionContext,
      this.m_examineGenericQuantity
    );
    this.m_examineGenericToken = null;
    this.m_examineGenericItemData = null;
    this.m_examineGenericQuantity = 0;
    this.m_examineGenericActionContext = null;
  }
  
  private final func ExamineInteractionLoadClothingFactory(itemRecord: wref<Item_Record>, itemID: ItemID, itemData: wref<gameItemData>, player: wref<PlayerPuppet>) -> Void {
    let templatePath: ResRef;
    let token: ref<ResourceToken>;
  
    if !IsDefined(itemRecord) || !IsDefined(player) {
      return;
    }
  
    templatePath = ExamineInteractionClothingFactory.ResolveTemplate(itemRecord.EntityName());
    token = GameInstance.GetResourceDepot().LoadResource(templatePath);
    if !IsDefined(token) {
      FTLog(s"[ExamineInteraction] Clothing factory load failed: template=\(ResRef.ToString(templatePath))");
      return;
    }

    this.PlayExamineLootSound(itemRecord, itemData);
    this.m_examineClothingToken = token;
    this.m_examineClothingTemplatePath = templatePath;
    this.m_examineClothingGender = player.GetResolvedGenderName();
    this.m_examineClothingBaseAppearance = ExamineInteractionClothingFactory.ResolveBaseAppearance(
      itemRecord,
      itemID,
      this.m_examineClothingGender
    );
    this.m_examineClothingEntityName = itemRecord.EntityName();
    this.m_examineClothingItemID = itemID;
    this.m_examineClothingItemData = itemData;
    this.m_examineClothingActionContext = this.BuildInspectionLootActionContext(this.m_examineInteractionData, itemID, itemData);
  
    if token.IsLoaded() {
      this.ExamineInteractionCompleteClothingFactory(token);
    } else if token.IsFailed() {
      FTLog(s"[ExamineInteraction] Clothing factory resource failed immediately: template=\(ResRef.ToString(templatePath))");
    } else {
      token.RegisterCallback(this, n"OnExamineInteractionClothingFactoryReady");
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Clothing factory resource requested: template=\(ResRef.ToString(templatePath))");
    }
  }
  
  private cb func OnExamineInteractionClothingFactoryReady(token: ref<ResourceToken>) -> Void {
    this.ExamineInteractionCompleteClothingFactory(token);
  }
  
  private final func ExamineInteractionCompleteClothingFactory(token: ref<ResourceToken>) -> Void {
    let appearanceName: CName;
    let template: ref<entEntityTemplate>;
  
    if !IsDefined(token)
      || !Equals(token.GetPath(), this.m_examineClothingTemplatePath)
      || token.IsFailed()
      || !token.IsLoaded() {
      FTLog("[ExamineInteraction] Clothing factory completion ignored: resource token is stale or failed.");
      return;
    }
  
    template = token.GetResource() as entEntityTemplate;
    appearanceName = ExamineInteractionClothingFactory.ResolveAppearance(
      template,
      this.m_examineClothingBaseAppearance,
      this.m_examineClothingGender,
      this.m_examineClothingItemID
    );
  
    if Equals(appearanceName, n"") {
      FTLog(s"[ExamineInteraction] Clothing preview suppressed: factory has no TPP or plain appearance entry for base=\(NameToString(this.m_examineClothingBaseAppearance)) gender=\(NameToString(this.m_examineClothingGender)) template=\(ResRef.ToString(this.m_examineClothingTemplatePath))");
      return;
    }
  
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Resolved clothing from authored factory appearances: entityName=\(NameToString(this.m_examineClothingEntityName)) template=\(ResRef.ToString(this.m_examineClothingTemplatePath)) appearance=\(NameToString(appearanceName))");
    ExamineInteractionPopup.ShowResolved(
      this.m_examineClothingTemplatePath,
      appearanceName,
      this.m_examineClothingItemID,
      this.m_examineClothingItemData,
      this.GetPlayer(),
      this.m_controller,
      this.m_examineClothingActionContext
    );
    this.m_examineClothingToken = null;
    this.m_examineClothingItemData = null;
    this.m_examineClothingActionContext = null;
  }
  
}

module MisterChedda.ExamineInteraction

/// Builds an engine-owned item drop through the same LootManager producer used by normal gameplay. The producer is async: the redscript RTTI advertises a Bool result, but the native implementation returns void and queues the work
public class ExamineInteractionWeaponPreviewFactory extends IScriptable {
  private let m_active: Bool;
  private let m_presented: Bool;
  private let m_dropSubmitted: Bool;
  private let m_pollCount: Int32;
  private let m_captureHandler: ref<CallbackSystemHandler>;
  private let m_capturePosition: Vector4;
  private let m_dropID: EntityID;
  private let m_drop: wref<gameItemDropObject>;
  private let m_player: wref<PlayerPuppet>;
  private let m_requester: wref<inkGameController>;
  private let m_sourceItem: wref<ItemObject>;
  private let m_sourceOwner: wref<GameObject>;
  private let m_sourceItemID: ItemID;
  private let m_temporaryItemID: ItemID;
  private let m_sourceItemData: wref<gameItemData>;
  private let m_actionContext: ref<ExamineInteractionLootActionContext>;
  private let m_playerItemsBefore: array<ItemID>;
  private let m_sourceQuantityBefore: Int32;
  private let m_weaponPresentation: Bool;

  public final func IsActive() -> Bool {
    return this.m_active;
  }

  public final func Begin(
    itemID: ItemID,
    itemData: wref<gameItemData>,
    sourceItem: wref<ItemObject>,
    sourceOwner: wref<GameObject>,
    player: wref<PlayerPuppet>,
    requester: wref<inkGameController>,
    actionContext: ref<ExamineInteractionLootActionContext>,
    weaponPresentation: Bool
  ) -> Bool {
    let transactionSystem: ref<TransactionSystem>;
    let playerItems: array<wref<gameItemData>>;
    let i: Int32;

    if this.m_active {
      FTLog("[ExamineInteraction] Item preview request ignored because an asynchronous item factory is already active.");
      return false;
    }
    if !ItemID.IsValid(itemID)
      || !IsDefined(itemData)
      || !IsDefined(sourceOwner)
      || !IsDefined(player)
      || !IsDefined(requester) {
      FTLog("[ExamineInteraction] Item preview factory rejected incomplete source item data.");
      return false;
    }

    transactionSystem = GameInstance.GetTransactionSystem(player.GetGame());
    if !IsDefined(GameInstance.GetLootManager(player.GetGame())) || !IsDefined(transactionSystem) {
      FTLog("[ExamineInteraction] Item preview factory could not acquire LootManager or TransactionSystem.");
      return false;
    }

    this.m_active = true;
    this.m_presented = false;
    this.m_dropSubmitted = false;
    this.m_pollCount = 0;
    this.m_player = player;
    this.m_requester = requester;
    this.m_sourceItem = sourceItem;
    this.m_sourceOwner = sourceOwner;
    this.m_sourceItemID = itemID;
    this.m_sourceItemData = itemData;
    this.m_actionContext = actionContext;
    this.m_weaponPresentation = weaponPresentation;
    ArrayClear(this.m_playerItemsBefore);
    transactionSystem.GetItemList(player, playerItems);
    i = 0;
    while i < ArraySize(playerItems) {
      if IsDefined(playerItems[i]) {
        ArrayPush(this.m_playerItemsBefore, playerItems[i].GetID());
      }
      i += 1;
    }
    this.m_sourceQuantityBefore = transactionSystem.GetItemQuantity(sourceOwner, itemID);
    this.m_capturePosition = player.GetWorldPosition()
      - Quaternion.GetForward(player.GetWorldOrientation()) * 2.0;
    this.m_capturePosition.Z += 1.0;

    // Photo Mode uses the same operation to copy generated items to its render puppet. It retains the concrete ItemID, parts and visual state
    if !transactionSystem.GiveItemByItemData(player, itemData) {
      FTLog("[ExamineInteraction] Item preview factory could not clone the exact gameItemData into temporary player ownership.");
      this.Abort();
      return false;
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Temporary exact item ownership requested asynchronously: item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(itemID))) playerInventorySnapshot=\(ArraySize(this.m_playerItemsBefore)) sourceQuantity=\(this.m_sourceQuantityBefore)");
    this.SchedulePoll();
    return true;
  }

  private cb func OnDropAttached(evt: ref<EntityLifecycleEvent>) -> Void {
    let distance: Float;
    let drop = evt.GetEntity() as gameItemDropObject;

    if !this.m_active || this.m_presented || !IsDefined(drop) {
      return;
    }
    if EntityID.IsDefined(this.m_dropID) {
      return;
    }
    if IsDefined(this.m_sourceOwner)
      && Equals(drop.GetEntityID(), this.m_sourceOwner.GetEntityID()) {
      return;
    }

    distance = Vector4.Distance(drop.GetWorldPosition(), this.m_capturePosition);
    if distance > 3.0 {
      return;
    }

    this.m_drop = drop;
    this.m_dropID = drop.GetEntityID();
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Vanilla item preview wrapper candidate captured: id=\(EntityID.ToDebugString(this.m_dropID)) distance=\(distance) template=\(ResRef.ToString(drop.GetTemplatePath()))");
  }

  public final func Poll() -> Void {
    let drop: ref<gameItemDropObject>;
    let emptyID: EntityID;
    let handler: ref<CallbackSystemHandler>;
    let itemObject: ref<ItemObject>;
    let lootManager: ref<LootManager>;
    let playerItems: array<wref<gameItemData>>;
    let candidateID: ItemID;
    let i: Int32;
    let transactionSystem: ref<TransactionSystem>;

    if !this.m_active || this.m_presented || !IsDefined(this.m_player) {
      return;
    }

    if !this.m_dropSubmitted {
      transactionSystem = GameInstance.GetTransactionSystem(this.m_player.GetGame());
      if !IsDefined(transactionSystem) {
        FTLog("[ExamineInteraction] Weapon preview ownership wait failed: TransactionSystem disappeared.");
        this.Abort();
        return;
      }

      transactionSystem.GetItemList(this.m_player, playerItems);
      i = 0;
      while i < ArraySize(playerItems) && !ItemID.IsValid(this.m_temporaryItemID) {
        if IsDefined(playerItems[i]) {
          candidateID = playerItems[i].GetID();
          if ItemID.GetTDBID(candidateID) == ItemID.GetTDBID(this.m_sourceItemID)
            && !ArrayContains(this.m_playerItemsBefore, candidateID) {
            this.m_temporaryItemID = candidateID;
          }
        }
        i += 1;
      }

      if !ItemID.IsValid(this.m_temporaryItemID) {
        this.m_pollCount += 1;
        if this.m_pollCount >= 100 {
          FTLog(s"[ExamineInteraction] Temporary exact weapon ownership timed out after 5.00 seconds: inventorySnapshot=\(ArraySize(this.m_playerItemsBefore)) currentInventory=\(ArraySize(playerItems))");
          this.Abort();
          return;
        }
        this.SchedulePoll();
        return;
      }

      lootManager = GameInstance.GetLootManager(this.m_player.GetGame());
      if !IsDefined(lootManager) {
        FTLog("[ExamineInteraction] Weapon preview drop submission failed: LootManager disappeared.");
        this.Abort();
        return;
      }

      handler = GameInstance.GetCallbackSystem()
        .RegisterCallback(n"Entity/AfterAttach", this, n"OnDropAttached");
      handler.AddTarget(EntityTarget.Type(NameOf<gameItemDropObject>()));
      this.m_captureHandler = handler;
      this.m_dropSubmitted = true;
      this.m_pollCount = 0;

      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Temporary concrete weapon clone detected: item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(this.m_temporaryItemID))) inventorySnapshot=\(ArraySize(this.m_playerItemsBefore)) currentInventory=\(ArraySize(playerItems))");

      // Intentionally ignore the declared Bool. Native Runtime_LootManager_SpawnItemDrop is void and submits an asynchronous item-factory request
      lootManager.SpawnItemDrop(
        this.m_player,
        this.m_temporaryItemID,
        this.m_capturePosition,
        this.m_player.GetWorldOrientation()
      );
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] Vanilla item preview drop submitted with the tracked temporary concrete ItemID.");
      this.SchedulePoll();
      return;
    }

    drop = this.m_drop;
    if !IsDefined(drop) && EntityID.IsDefined(this.m_dropID) {
      drop = GameInstance.FindEntityByID(this.m_player.GetGame(), this.m_dropID) as gameItemDropObject;
      this.m_drop = drop;
    }

    if IsDefined(drop) {
      itemObject = drop.GetItemObject();
      if IsDefined(itemObject) {
        if itemObject.GetItemID() != this.m_temporaryItemID {
          // Another nearby gameplay drop may attach during the capture window. Leave it entirely untouched and continue waiting for our own wrapper
          ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Item preview factory ignored an unrelated drop child: expected=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(this.m_temporaryItemID))) actual=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(itemObject.GetItemID())))");
          this.m_drop = null;
          this.m_dropID = emptyID;
          this.SchedulePoll();
          return;
        }

        this.m_presented = true;
        this.UnregisterCapture();
        FTLog(s"[ExamineInteraction] Item preview assembly succeeded: item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(itemObject.GetItemID()))) template=\(ResRef.ToString(itemObject.GetTemplatePath())) appearance=\(NameToString(itemObject.GetCurrentAppearanceName())) weaponPresentation=\(this.m_weaponPresentation)");
        ExamineInteractionPopup.ShowAssembledItem(
          itemObject,
          this.m_sourceItem,
          drop,
          itemObject.GetItemID(),
          itemObject.GetItemData(),
          this.m_player,
          this.m_requester,
          this.m_actionContext,
          this.m_weaponPresentation,
          this
        );
        return;
      }
    }

    this.m_pollCount += 1;
    if this.m_pollCount >= 200 {
      FTLog(s"[ExamineInteraction] Vanilla item preview assembly timed out after 10.00 seconds: wrapperCaptured=\(EntityID.IsDefined(this.m_dropID))");
      this.Abort();
      return;
    }
    this.SchedulePoll();
  }

  public final func ReleasePreview() -> Void {
    if !this.m_active {
      return;
    }
    this.CleanupTemporaryState();
    ExamineInteractionLog.Diagnostic("[ExamineInteraction] Temporary vanilla item preview released.");
  }

  public final func Abort() -> Void {
    if !this.m_active {
      return;
    }
    this.CleanupTemporaryState();
    ExamineInteractionLog.Diagnostic("[ExamineInteraction] Temporary vanilla item preview factory aborted and cleaned up.");
  }

  private final func CleanupTemporaryState() -> Void {
    let drop: ref<gameItemDropObject>;
    let emptyID: EntityID;
    let itemObject: ref<ItemObject>;
    let transactionSystem: ref<TransactionSystem>;

    this.UnregisterCapture();
    if IsDefined(this.m_player) {
      transactionSystem = GameInstance.GetTransactionSystem(this.m_player.GetGame());
    }

    drop = this.m_drop;
    if !IsDefined(drop) && IsDefined(this.m_player) && EntityID.IsDefined(this.m_dropID) {
      drop = GameInstance.FindEntityByID(this.m_player.GetGame(), this.m_dropID) as gameItemDropObject;
    }
    if IsDefined(transactionSystem) && IsDefined(drop) {
      itemObject = drop.GetItemObject();
      if IsDefined(itemObject) && itemObject.GetItemID() == this.m_temporaryItemID {
        transactionSystem.RemoveItem(drop, itemObject.GetItemID(), 1);
      } else if ItemID.IsValid(this.m_temporaryItemID)
        && transactionSystem.HasItem(drop, this.m_temporaryItemID) {
        transactionSystem.RemoveItem(drop, this.m_temporaryItemID, 1);
      }
    }

    // GiveItemByItemData produces a new concrete ItemID. Remove precisely that tracked clone if the drop producer did not consume it, leaving every pre-existing player instance of the same weapon untouched
    if IsDefined(transactionSystem)
      && IsDefined(this.m_player)
      && ItemID.IsValid(this.m_temporaryItemID)
      && transactionSystem.HasItem(this.m_player, this.m_temporaryItemID) {
      transactionSystem.RemoveItem(this.m_player, this.m_temporaryItemID, 1);
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] Tracked temporary item clone removed from player inventory.");
    }

    this.m_active = false;
    this.m_presented = false;
    this.m_dropSubmitted = false;
    this.m_pollCount = 0;
    this.m_drop = null;
    this.m_dropID = emptyID;
    this.m_player = null;
    this.m_requester = null;
    this.m_sourceItem = null;
    this.m_sourceOwner = null;
    this.m_sourceItemID = ItemID.None();
    this.m_temporaryItemID = ItemID.None();
    this.m_sourceItemData = null;
    this.m_actionContext = null;
    this.m_weaponPresentation = false;
    ArrayClear(this.m_playerItemsBefore);
  }

  private final func SchedulePoll() -> Void {
    if !this.m_active || !IsDefined(this.m_player) {
      return;
    }
    GameInstance.GetDelaySystem(this.m_player.GetGame()).DelayCallback(
      ExamineInteractionWeaponPreviewPoll.Create(this),
      0.05,
      false
    );
  }

  private final func UnregisterCapture() -> Void {
    if IsDefined(this.m_captureHandler) && this.m_captureHandler.IsRegistered() {
      this.m_captureHandler.Unregister();
    }
    this.m_captureHandler = null;
  }
}

module MisterChedda.ExamineInteraction

import Codeware.UI.*
import MisterChedda.ExamineInteraction.Native.*

public enum ExamineInspectionTextCategory {
  Lootable = 0,
  Weapon = 1,
  Clothing = 2,
  WorldProp = 3
}

public class ExamineInteractionPopup extends CustomPopup {
  private let m_templatePath: ResRef;
  private let m_appearanceName: CName;
  private let m_sourceItem: wref<ItemObject>;
  private let m_sourceEntity: wref<Entity>;
  private let m_hiddenSourceVisuals: array<CName>;
  private let m_sourceVisualsHidden: Bool;
  private let m_sourceOrientation: Quaternion;
  private let m_cameraOrientation: Quaternion;
  private let m_previewEntityID: EntityID;
  private let m_previewLightEntityID: EntityID;
  private let m_previewReady: Bool;
  private let m_previewAttachCallbackRegistered: Bool;
  private let m_localPivot: Vector4;
  private let m_hasLocalPivot: Bool;
  private let m_previewHalfExtents: Vector4;
  private let m_previewRadius: Float;
  private let m_previewScale: Float = 1.0;
  private let m_distance: Float;
  private let m_framedDistance: Float;
  private let m_environmentHitDistance: Float;
  private let m_previewBoundsPrepared: Bool;
  private let m_pitchOffset: Float;
  private let m_yawOffset: Float;
  private let m_dragging: Bool;
  private let m_keyInputHandler: ref<CallbackSystemHandler>;
  private let m_axisInputHandler: ref<CallbackSystemHandler>;
  private let m_previewFovCaptured: Bool;
  private let m_previewBaseFov: Float;
  private let m_previewAppliedFov: Float;
  private let m_previewProjectionBaseline: Float;
  private let m_transactionPreview: Bool;
  private let m_transactionPreviewEntity: wref<ItemObject>;
  private let m_transactionPreviewOwner: wref<gameItemDropObject>;
  private let m_transactionPreviewItemID: ItemID;
  private let m_itemPreviewFactory: ref<ExamineInteractionWeaponPreviewFactory>;
  private let m_assembledWeaponPreview: Bool;
  private let m_borrowedWorldWeapon: Bool;
  private let m_borrowedWeaponHighlightSuppressed: Bool;
  private let m_borrowedWorldTransform: WorldTransform;
  private let m_worldMeshPreview: Bool;
  private let m_worldEntityPreview: Bool;
  private let m_worldMeshPath: ResRef;
  private let m_worldMeshAppearance: CName;
  private let m_cameraLocalFacingFlip: Bool;
  private let m_worldMeshGrouped: Bool;
  private let m_worldMeshSelectionIndex: Int32;
  private let m_worldMeshSelectionCount: Int32;
  private let m_sourceWorldNode: wref<worldINodeInstance>;
  private let m_sourceWorldNodeHidden: Bool;
  private let m_inspectionTitle: String;
  private let m_inspectionType: String;
  private let m_inspectionDescription: String;
  private let m_inspectionTier: String;
  private let m_inspectionPrice: String;
  private let m_inspectionTierColor: HDRColor;
  private let m_inspectionTextCategory: ExamineInspectionTextCategory;
  private let m_hasAuthoredScannerText: Bool;
  private let m_inventoryCapacityWarning: Bool;
  private let m_hintRoot: ref<inkCanvas>;
  private let m_keyboardHint: ref<inkHorizontalPanel>;
  private let m_controllerHint: ref<inkHorizontalPanel>;
  private let m_inputDeviceCallback: ref<CallbackHandle>;
  private let m_actionContext: ref<ExamineInteractionLootActionContext>;
  private let m_actionPlayer: wref<PlayerPuppet>;
  private let m_actionTriggered: Bool;

  public static func Show(itemObject: ref<ItemObject>, itemData: wref<gameItemData>, player: wref<PlayerPuppet>, requester: wref<inkGameController>, actionContext: ref<ExamineInteractionLootActionContext>) -> Void {
    let neutralOrientation: EulerAngles;
    let popup: ref<ExamineInteractionPopup>;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();

    if !IsDefined(itemObject) || !IsDefined(requester) {
      FTLog("[ExamineInteraction] Inspection popup failed: item or requester is unavailable.");
      return;
    }

    // Clean up a preview left behind by a script reload or interrupted popup
    if IsDefined(staticEntitySystem) {
      staticEntitySystem.DespawnTagged(n"MisterCheddaExamineInteractionPreview");
    }

    popup = new ExamineInteractionPopup();
    popup.m_sourceItem = itemObject;
    popup.m_sourceEntity = itemObject;
    popup.m_actionContext = actionContext;
    popup.m_actionPlayer = player;
    popup.ConfigureItemInformation(itemObject.GetItemID(), itemData, player, actionContext);
    if Equals(popup.m_inspectionTextCategory, ExamineInspectionTextCategory.Clothing) {
      popup.m_yawOffset = 180.0;
    }
    popup.m_templatePath = itemObject.GetTemplatePath();
    popup.m_appearanceName = itemObject.GetCurrentAppearanceName();
    popup.m_sourceOrientation = itemObject.GetWorldOrientation();
    popup.m_distance = 0.42;
    popup.Open(requester);
  }

  public static func ShowResolved(templatePath: ResRef, appearanceName: CName, itemID: ItemID, itemData: wref<gameItemData>, player: wref<PlayerPuppet>, requester: wref<inkGameController>, actionContext: ref<ExamineInteractionLootActionContext>, opt itemQuantity: Int32) -> Void {
    let neutralOrientation: EulerAngles;
    let popup: ref<ExamineInteractionPopup>;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();

    if !ResRef.IsValid(templatePath) || Equals(appearanceName, n"") || !IsDefined(requester) {
      FTLog("[ExamineInteraction] Resolved inspection popup failed: template, appearance, or requester is unavailable.");
      return;
    }

    if IsDefined(staticEntitySystem) {
      staticEntitySystem.DespawnTagged(n"MisterCheddaExamineInteractionPreview");
    }

    popup = new ExamineInteractionPopup();
    popup.ConfigureItemInformation(itemID, itemData, player, actionContext, itemQuantity);
    if Equals(popup.m_inspectionTextCategory, ExamineInspectionTextCategory.Clothing) {
      popup.m_yawOffset = 180.0;
    }
    popup.m_actionContext = actionContext;
    popup.m_actionPlayer = player;
    popup.m_templatePath = templatePath;
    popup.m_appearanceName = appearanceName;
    popup.m_sourceOrientation = EulerAngles.ToQuat(neutralOrientation);
    popup.m_distance = 0.42;
    popup.Open(requester);
  }

  public static func ShowWorldMesh(sourceNode: wref<worldINodeInstance>, meshPath: ResRef, meshAppearance: CName, requester: wref<inkGameController>) -> Void {
    let neutralOrientation: EulerAngles;
    let popup: ref<ExamineInteractionPopup>;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();

    if !IsDefined(sourceNode) || !ResRef.IsValid(meshPath) || !IsDefined(requester) {
      FTLog("[ExamineInteraction] World-mesh popup failed: node, mesh, or requester is unavailable.");
      return;
    }

    if IsDefined(staticEntitySystem) {
      staticEntitySystem.DespawnTagged(n"MisterCheddaExamineInteractionPreview");
    }

    popup = new ExamineInteractionPopup();
    popup.m_worldMeshPreview = true;
    popup.m_worldMeshPath = meshPath;
    popup.m_worldMeshAppearance = meshAppearance;
    popup.ConfigureWorldMeshInformation(meshPath);
    popup.m_sourceWorldNode = sourceNode;
    popup.m_worldMeshGrouped = IsWorldNodeGrouped(sourceNode);
    popup.m_worldMeshSelectionIndex = GetWorldNodeSelectionIndex(sourceNode);
    popup.m_worldMeshSelectionCount = GetWorldNodeSelectionCount(sourceNode);
    popup.m_templatePath = r"misterchedda\\examine_interaction\\entities\\examine_mesh_preview.ent";
    popup.m_appearanceName = n"None";
    popup.m_sourceOrientation = EulerAngles.ToQuat(neutralOrientation);
    popup.m_distance = 0.42;
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] World prop presentation configured: cameraLocalFlip=false grouped=\(popup.m_worldMeshGrouped) selection=\(popup.m_worldMeshSelectionIndex)/\(popup.m_worldMeshSelectionCount) mesh=\(ResRef.ToString(meshPath))");
    popup.Open(requester);
  }

  public static func ShowWorldEntity(sourceEntity: wref<Entity>, requester: wref<inkGameController>) -> Void {
    let appearanceName: CName;
    let neutralOrientation: EulerAngles;
    let popup: ref<ExamineInteractionPopup>;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();
    let templatePath: ResRef;

    if !IsDefined(sourceEntity) || !IsDefined(requester) {
      FTLog("[ExamineInteraction] World-entity popup failed: entity or requester is unavailable.");
      return;
    }

    templatePath = sourceEntity.GetTemplatePath();
    if !ResRef.IsValid(templatePath) {
      FTLog("[ExamineInteraction] World-entity popup failed: source entity has no valid template path.");
      return;
    }

    if IsDefined(staticEntitySystem) {
      staticEntitySystem.DespawnTagged(n"MisterCheddaExamineInteractionPreview");
    }

    appearanceName = sourceEntity.GetCurrentAppearanceName();
    if Equals(appearanceName, n"") {
      appearanceName = n"None";
    }

    popup = new ExamineInteractionPopup();
    popup.m_worldEntityPreview = true;
    popup.m_sourceEntity = sourceEntity;
    popup.m_templatePath = templatePath;
    popup.m_appearanceName = appearanceName;
    if StrFindFirst(StrLower(ResRef.ToString(templatePath)), "\\stash_weapons\\") >= 0 {
      popup.m_yawOffset = 90.0;
    }
    popup.m_cameraLocalFacingFlip = IsDefined(sourceEntity as Frame)
      || StrFindFirst(StrLower(ResRef.ToString(templatePath)), "poster") >= 0;
    popup.m_sourceOrientation = EulerAngles.ToQuat(neutralOrientation);
    popup.m_distance = 0.42;
    popup.ConfigureWorldMeshInformation(templatePath);
    popup.ConfigureWorldEntityScannerInformation(sourceEntity);
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Whole world-entity presentation configured: cameraLocalFlip=\(popup.m_cameraLocalFacingFlip) class=\(NameToString(sourceEntity.GetClassName())) template=\(ResRef.ToString(templatePath)) appearance=\(NameToString(appearanceName))");
    popup.Open(requester);
  }

  public static func ShowAssembledItem(previewItem: ref<ItemObject>, sourceItem: wref<ItemObject>, owner: wref<gameItemDropObject>, previewItemID: ItemID, itemData: wref<gameItemData>, player: wref<PlayerPuppet>, requester: wref<inkGameController>, actionContext: ref<ExamineInteractionLootActionContext>, weaponPresentation: Bool, factory: ref<ExamineInteractionWeaponPreviewFactory>) -> Void {
    let neutralOrientation: EulerAngles;
    let popup: ref<ExamineInteractionPopup>;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();

    if !IsDefined(previewItem)
      || !IsDefined(owner)
      || !ItemID.IsValid(previewItemID)
      || !IsDefined(requester) {
      FTLog("[ExamineInteraction] Assembled item popup failed: preview item, owner, ID, or requester is unavailable.");
      return;
    }

    if IsDefined(staticEntitySystem) {
      staticEntitySystem.DespawnTagged(n"MisterCheddaExamineInteractionPreview");
    }

    popup = new ExamineInteractionPopup();
    popup.m_transactionPreview = true;
    popup.m_transactionPreviewEntity = previewItem;
    popup.m_transactionPreviewOwner = owner;
    popup.m_transactionPreviewItemID = previewItemID;
    popup.m_itemPreviewFactory = factory;
    popup.m_assembledWeaponPreview = weaponPresentation;
    popup.ConfigureItemInformation(previewItemID, itemData, player, actionContext);
    popup.m_sourceItem = sourceItem;
    popup.m_sourceEntity = sourceItem;
    popup.m_actionContext = actionContext;
    popup.m_actionPlayer = player;
    popup.m_sourceOrientation = EulerAngles.ToQuat(neutralOrientation);
    popup.m_yawOffset = weaponPresentation ? 90.0 : 0.0;
    popup.m_distance = 0.42;
    popup.Open(requester);
  }

  public static func ShowBorrowedWorldWeapon(previewItem: ref<ItemObject>, owner: wref<gameItemDropObject>, previewItemID: ItemID, itemData: wref<gameItemData>, player: wref<PlayerPuppet>, requester: wref<inkGameController>, actionContext: ref<ExamineInteractionLootActionContext>) -> Void {
    let neutralOrientation: EulerAngles;
    let popup: ref<ExamineInteractionPopup>;

    if !IsDefined(previewItem)
      || !IsDefined(owner)
      || !ItemID.IsValid(previewItemID)
      || !IsDefined(requester) {
      FTLog("[ExamineInteraction] Borrowed weapon popup failed: preview item, owner, ID, or requester is unavailable.");
      return;
    }

    popup = new ExamineInteractionPopup();
    popup.m_transactionPreview = true;
    popup.m_borrowedWorldWeapon = true;
    popup.m_transactionPreviewEntity = previewItem;
    popup.m_transactionPreviewOwner = owner;
    popup.m_transactionPreviewItemID = previewItemID;
    popup.ConfigureItemInformation(previewItemID, itemData, player, actionContext);
    popup.m_actionContext = actionContext;
    popup.m_actionPlayer = player;
    popup.m_borrowedWorldTransform = owner.GetWorldTransform();
    popup.m_sourceOrientation = EulerAngles.ToQuat(neutralOrientation);
    popup.m_yawOffset = 90.0;
    popup.m_distance = 0.42;
    popup.SuppressBorrowedWorldWeaponHighlight();
    popup.Open(requester);
  }

  public func GetQueueName() -> CName {
    return n"examine_interaction_popup";
  }

  public func UseCursor() -> Bool {
    return false;
  }

  private func ConfigureItemInformation(itemID: ItemID, itemData: wref<gameItemData>, player: wref<PlayerPuppet>, actionContext: ref<ExamineInteractionLootActionContext>, opt itemQuantity: Int32) -> Void {
    let brokenWeapon: Bool;
    let itemRecord: wref<Item_Record>;
    let itemTypeKey: String;
    let quality: gamedataQuality;
    let sellPrice: Int32;

    if !ItemID.IsValid(itemID) {
      return;
    }

    itemRecord = TweakDBInterface.GetItemRecord(ItemID.GetTDBID(itemID));
    if !IsDefined(itemRecord) {
      return;
    }

    this.m_inspectionTitle = GetLocalizedItemNameByCName(itemRecord.DisplayName());
    if IsDefined(itemRecord as WeaponItem_Record) {
      this.m_inspectionTextCategory = ExamineInspectionTextCategory.Weapon;
    } else if IsDefined(itemRecord as Clothing_Record) {
      this.m_inspectionTextCategory = ExamineInspectionTextCategory.Clothing;
    } else {
      this.m_inspectionTextCategory = ExamineInspectionTextCategory.Lootable;
    }
    if IsDefined(itemRecord.ItemType()) {
      itemTypeKey = UIItemsHelper.GetItemTypeKey(itemRecord.ItemType().Type());
      if IsStringValid(itemTypeKey) {
        this.m_inspectionType = GetLocalizedText(itemTypeKey);
      }
    }
    this.m_inspectionDescription = GetLocalizedText(LocKeyToString(itemRecord.LocalizedDescription()));

    if IsDefined(itemData) {
      brokenWeapon = IsDefined(itemRecord as WeaponItem_Record) && RPGManager.IsItemBroken(itemData);
      quality = RPGManager.GetItemDataQuality(itemData);
      if brokenWeapon {
        this.m_inspectionTier = "BROKEN";
        this.m_inspectionTierColor = HDRColor(1.00, 0.22, 0.18, 1.0);
        this.m_inspectionDescription = this.ResolveBrokenWeaponComponentDescription(itemID, player, actionContext);
        this.m_inspectionPrice = "";
      } else if NotEquals(quality, gamedataQuality.Random) && NotEquals(quality, gamedataQuality.Invalid) {
        if Equals(quality, gamedataQuality.Iconic) {
          this.m_inspectionTier = GetLocalizedText("Gameplay-RPG-Stats-Tiers-Tier5");
        } else {
          this.m_inspectionTier = GetLocalizedText(UIItemsHelper.QualityToTierPlusString(quality));
        }
        this.m_inspectionTierColor = this.GetInspectionTierColor(quality);
      }

      if brokenWeapon {
        this.m_inspectionPrice = "";
      } else if itemData.HasTag(n"Currency") && itemQuantity > 0 {
        this.m_inspectionPrice = IntToString(itemQuantity);
      } else if IsDefined(player) {
        sellPrice = RPGManager.CalculateSellPriceItemData(player.GetGame(), player, itemData);
        this.m_inspectionPrice = IntToString(sellPrice);
      }

      this.m_inventoryCapacityWarning = this.ShouldShowInventoryCapacityWarning(itemData, player, actionContext);
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Inspection information resolved: title=\(this.m_inspectionTitle) type=\(this.m_inspectionType) tier=\(this.m_inspectionTier) sellValue=\(this.m_inspectionPrice) descriptionAvailable=\(IsStringValid(this.m_inspectionDescription))");
  }

  private func ShouldShowInventoryCapacityWarning(itemData: wref<gameItemData>, player: wref<PlayerPuppet>, actionContext: ref<ExamineInteractionLootActionContext>) -> Bool {
    let action: CName;
    let carryCapacity: Float;
    let i: Int32;
    let itemWeight: Float;
    let transfersToInventory: Bool;

    if !IsDefined(itemData) || !IsDefined(player) || !IsDefined(actionContext) {
      return false;
    }

    while i < ArraySize(actionContext.actions) {
      action = actionContext.actions[i];
      if Equals(action, n"Loot")
        || Equals(action, n"Take")
        || Equals(action, n"Equip")
        || Equals(action, n"EquipItem") {
        transfersToInventory = true;
        break;
      }
      i += 1;
    }

    if !transfersToInventory {
      return false;
    }

    itemWeight = RPGManager.GetItemWeight(itemData);
    if itemWeight <= 0.0 {
      return false;
    }

    carryCapacity = GameInstance.GetStatsSystem(player.GetGame()).GetStatValue(
      Cast<StatsObjectID>(player.GetEntityID()),
      gamedataStatType.CarryCapacity
    );
    return player.m_curInventoryWeight + itemWeight > carryCapacity;
  }

  private func ResolveBrokenWeaponComponentDescription(itemID: ItemID, player: wref<PlayerPuppet>, actionContext: ref<ExamineInteractionLootActionContext>) -> String {
    let components: array<IngredientData>;
    let componentQuality: gamedataQuality;
    let craftingSystem: ref<CraftingSystem>;
    let description: String;
    let localizationKey = "UI_MisterChedda_Examine_BrokenWeapon_DisassemblyResult";
    let owner: ref<GameObject>;
    let restoredAttachments: array<ItemAttachments>;
    let tier: String;

    if !IsDefined(player) || !IsDefined(actionContext) {
      return "";
    }

    owner = GameInstance.FindEntityByID(player.GetGame(), actionContext.ownerID) as GameObject;
    craftingSystem = CraftingSystem.GetInstance(player.GetGame());
    if !IsDefined(owner) || !IsDefined(craftingSystem) {
      return "";
    }

    components = craftingSystem.GetDisassemblyResultItems(owner, itemID, 1, restoredAttachments, true);
    if ArraySize(components) != 1 || components[0].quantity <= 0 || !IsDefined(components[0].id) {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Broken-weapon component preview unavailable: resultCount=\(ArraySize(components)) item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(itemID)))");
      return "";
    }

    componentQuality = RPGManager.GetItemQualityFromRecord(components[0].id);
    if Equals(componentQuality, gamedataQuality.Random) || Equals(componentQuality, gamedataQuality.Invalid) {
      return "";
    }

    tier = GetLocalizedText(UIItemsHelper.QualityToTierPlusString(componentQuality));
    if !IsStringValid(tier) {
      return "";
    }

    description = GetLocalizedTextByKey(StringToName(localizationKey));
    if !IsStringValid(description) || Equals(description, localizationKey) {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Broken-weapon component localization is unavailable: key=\(localizationKey)");
      return "";
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Broken-weapon component preview resolved: quantity=\(components[0].quantity) tier=\(tier) item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(itemID)))");
    description = StrReplace(description, "{quantity}", IntToString(components[0].quantity));
    description = StrReplace(description, "{tier}", tier);
    return description;
  }

  private func GetInspectionTierColor(quality: gamedataQuality) -> HDRColor {
    switch quality {
      case gamedataQuality.Uncommon:
      case gamedataQuality.UncommonPlus:
        return HDRColor(0.35, 1.00, 0.20, 1.0);
      case gamedataQuality.Rare:
      case gamedataQuality.RarePlus:
        return HDRColor(0.16, 0.72, 1.00, 1.0);
      case gamedataQuality.Epic:
      case gamedataQuality.EpicPlus:
        return HDRColor(0.76, 0.32, 1.00, 1.0);
      case gamedataQuality.Legendary:
      case gamedataQuality.LegendaryPlus:
      case gamedataQuality.LegendaryPlusPlus:
      case gamedataQuality.Iconic:
        return HDRColor(1.00, 0.52, 0.10, 1.0);
    }
    return HDRColor(0.72, 0.76, 0.80, 1.0);
  }

  private func IsInspectionNameDigits(value: String, startIndex: Int32) -> Bool {
    let i = startIndex;
    let length = StrLen(value);

    if startIndex >= length {
      return false;
    }

    while i < length {
      if !StrContains("0123456789", StrMid(value, i, 1)) {
        return false;
      }
      i += 1;
    }
    return true;
  }

  private func IsInspectionShortWord(value: String) -> Bool {
    return Equals(value, "ai")
      || Equals(value, "cd")
      || Equals(value, "fx")
      || Equals(value, "id")
      || Equals(value, "pc")
      || Equals(value, "tv")
      || Equals(value, "ui")
      || Equals(value, "vr")
      || Equals(value, "vhs");
  }

  private func IsInspectionVariantToken(token: String, index: Int32, tokenCount: Int32) -> Bool {
    let length: Int32;
    let lower = StrLower(token);

    length = StrLen(lower);
    if Equals(lower, "mq000")
      || Equals(lower, "mq001")
      || Equals(lower, "mq002")
      || Equals(lower, "q302") {
      return true;
    }
    if length == 1 {
      return true;
    }
    if length <= 2 && this.IsInspectionNameDigits(lower, 0) {
      return true;
    }
    if length >= 2 && Equals(StrMid(lower, 0, 1), "v") && this.IsInspectionNameDigits(lower, 1) {
      return true;
    }
    return index == tokenCount - 1 && length == 2 && !this.IsInspectionShortWord(lower);
  }

  private func FormatInspectionNameWord(token: String) -> String {
    let lower = StrLower(token);

    if this.IsInspectionShortWord(lower)
      || Equals(lower, "api")
      || Equals(lower, "cpu")
      || Equals(lower, "gpu")
      || Equals(lower, "led") {
      return StrUpper(lower);
    }
    return StrFrontToUpper(lower);
  }

  private func FormatWorldMeshName(meshPath: ResRef) -> String {
    let fileName: String;
    let i: Int32;
    let result: String;
    let separator: Int32;
    let stem: String;
    let tokens: array<String>;
    let path = StrReplace(ResRef.ToString(meshPath), "/", "\\");
    // "fake" is just the entity name here they all have fake in their ent file names
    let isStashWeapon = StrFindFirst(StrLower(path), "\\stash_weapons\\") >= 0;

    separator = StrFindLast(path, "\\");
    if separator >= 0 {
      fileName = StrMid(path, separator + 1, StrLen(path) - separator - 1);
    } else {
      fileName = path;
    }

    stem = StrReplace(StrReplace(fileName, ".mesh", ""), ".ent", "");
    tokens = StrSplit(stem, "_", false);
    while i < ArraySize(tokens) {
      if !(isStashWeapon && Equals(StrLower(tokens[i]), "fake"))
        && !this.IsInspectionVariantToken(tokens[i], i, ArraySize(tokens)) {
        if IsStringValid(result) {
          result += " ";
        }
        result += this.FormatInspectionNameWord(tokens[i]);
      }
      i += 1;
    }

    if IsStringValid(result) {
      return result;
    }
    return StrFrontToUpper(StrReplace(stem, "_", " "));
  }

  private func ConfigureWorldMeshInformation(meshPath: ResRef) -> Void {
    let overrideName = ExamineInteractionWorldPropNames.Resolve(meshPath);

    this.m_inspectionTextCategory = ExamineInspectionTextCategory.WorldProp;
    this.m_inspectionTitle = IsStringValid(overrideName)
      ? overrideName
      : this.FormatWorldMeshName(meshPath);
    this.m_inspectionType = "";
  }

  private func ApplyWorldEntityScannerRecord(recordID: TweakDBID) -> Bool {
    let description: String;
    let name: String;
    let record: ref<ScannableData_Record>;

    if !TDBID.IsValid(recordID) {
      return false;
    }

    record = TweakDBInterface.GetScannableDataRecord(recordID);
    if !IsDefined(record) {
      return false;
    }

    name = GetLocalizedText(LocKeyToString(record.LocalizedName()));
    description = GetLocalizedText(LocKeyToString(record.LocalizedDescription()));
    if !IsStringValid(name) && !IsStringValid(description) {
      return false;
    }

    if IsStringValid(name) {
      this.m_inspectionTitle = name;
    }
    if IsStringValid(description) {
      this.m_inspectionDescription = description;
    }
    this.m_hasAuthoredScannerText = true;
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] World entity scanner text resolved: record=\(TDBID.ToStringDEBUG(recordID)) name=\(name) description=\(description)");
    return true;
  }

  private func ConfigureWorldEntityScannerInformation(sourceEntity: wref<Entity>) -> Void {
    let clues: array<FocusClueDefinition>;
    let components: array<ref<IComponent>>;
    let customDescriptions: array<TweakDBID>;
    let i: Int32;
    let objectDescription: ref<ObjectScanningDescription>;
    let scanning: ref<ScanningComponent>;

    if !IsDefined(sourceEntity) {
      return;
    }

    components = sourceEntity.GetComponents();
    i = 0;
    while i < ArraySize(components) {
      scanning = components[i] as ScanningComponent;
      if IsDefined(scanning) {
        break;
      }
      i += 1;
    }
    if !IsDefined(scanning) {
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] World entity has no scanning component; retaining generated preview text.");
      return;
    }

    clues = scanning.GetAllClues();
    i = 0;
    while i < ArraySize(clues) {
      if clues[i].isEnabled && this.ApplyWorldEntityScannerRecord(clues[i].clueRecord) {
        return;
      }
      i += 1;
    }

    i = 0;
    while i < ArraySize(clues) {
      if this.ApplyWorldEntityScannerRecord(clues[i].clueRecord) {
        return;
      }
      i += 1;
    }

    objectDescription = scanning.GetObjectDescription();
    if !IsDefined(objectDescription) {
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] World entity scanning component has no readable clue or object-description record.");
      return;
    }
    if this.ApplyWorldEntityScannerRecord(objectDescription.GetGameplayDesription()) {
      return;
    }

    customDescriptions = objectDescription.GetCustomDesriptions();
    i = 0;
    while i < ArraySize(customDescriptions) {
      if this.ApplyWorldEntityScannerRecord(customDescriptions[i]) {
        return;
      }
      i += 1;
    }
    ExamineInteractionLog.Diagnostic("[ExamineInteraction] World entity scanning records did not resolve localized preview text.");
  }

  private func CreateInspectionMetadataLabel(parent: wref<inkCompoundWidget>, widgetName: CName, value: String, tint: HDRColor, leftSpacing: Float) -> Void {
    let label: ref<inkText>;

    if !IsDefined(parent) || !IsStringValid(value) {
      return;
    }

    label = new inkText();
    label.SetName(widgetName);
    label.SetText(value);
    label.SetFontFamily("base\\gameplay\\gui\\fonts\\orbitron\\orbitron.inkfontfamily");
    label.SetFontStyle(n"Regular");
    label.SetFontSize(38);
    label.SetTracking(4);
    label.SetLetterCase(textLetterCase.UpperCase);
    label.SetHorizontalAlignment(textHorizontalAlignment.Left);
    label.SetVerticalAlignment(textVerticalAlignment.Center);
    label.SetFitToContent(true);
    label.SetWrapping(false);
    label.SetMargin(inkMargin(leftSpacing, 0.0, 0.0, 0.0));
    label.SetTintColor(tint);
    label.Reparent(parent);
  }

  private func CreateInspectionMetadataSeparator(parent: wref<inkCompoundWidget>, widgetName: CName) -> Void {
    let separator: ref<inkText>;

    if !IsDefined(parent) {
      return;
    }

    // REEEE Orbitron does not have a bullet glyph
    separator = new inkText();
    separator.SetName(widgetName);
    separator.SetText("•");
    separator.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    separator.SetFontStyle(n"Medium");
    separator.SetFontSize(40);
    separator.SetTracking(2);
    separator.SetHorizontalAlignment(textHorizontalAlignment.Left);
    separator.SetVerticalAlignment(textVerticalAlignment.Center);
    separator.SetFitToContent(true);
    separator.SetWrapping(false);
    separator.SetMargin(inkMargin(24.0, 0.0, 0.0, 0.0));
    separator.SetTintColor(HDRColor(0.92, 0.94, 0.95, 1.0));
    separator.Reparent(parent);
  }

  private func CreateInspectionBackground() -> Void {
    let background: ref<inkImage>;

    if !this.IsInspectionTextEnabled() || !IsStringValid(this.m_inspectionTitle) {
      return;
    }

    background = new inkImage();
    background.SetName(n"ExamineInteractionInformationBackground");
    background.SetAnchor(inkEAnchor.Fill);
    background.SetHAlign(inkEHorizontalAlign.Fill);
    background.SetVAlign(inkEVerticalAlign.Fill);
    background.SetContentHAlign(inkEHorizontalAlign.Fill);
    background.SetContentVAlign(inkEVerticalAlign.Fill);
    background.SetAtlasResource(r"misterchedda\\examine_interaction\\icons\\bg.inkatlas");
    background.SetTexturePart(n"bg");
    background.Reparent(this.GetRootCompoundWidget());
  }

  private func CreateInventoryCapacityWarning(parent: wref<inkCompoundWidget>) -> Void {
    let attentionIcon: ref<inkImage>;
    let row: ref<inkHorizontalPanel>;
    let warningText: ref<inkText>;
    let warningValue: String;
    let weightIcon: ref<inkImage>;
    let yellow = HDRColor(1.0, 0.78, 0.12, 1.0);

    if !this.m_inventoryCapacityWarning || !IsDefined(parent) {
      return;
    }

    warningValue = GetLocalizedTextByKey(n"UI_MisterChedda_Examine_InventoryWillBeFull");
    if !IsStringValid(warningValue) || Equals(warningValue, "UI_MisterChedda_Examine_InventoryWillBeFull") {
      warningValue = "Inventory will be full once taken";
    }

    row = new inkHorizontalPanel();
    row.SetName(n"ExamineInteractionInventoryCapacityWarning");
    row.SetFitToContent(true);
    row.SetHAlign(inkEHorizontalAlign.Left);
    row.SetVAlign(inkEVerticalAlign.Top);
    row.SetMargin(inkMargin(0.0, 28.0, 0.0, 0.0));
    row.Reparent(parent);

    attentionIcon = new inkImage();
    attentionIcon.SetName(n"ExamineInteractionInventoryCapacityAttentionIcon");
    attentionIcon.SetSize(38.0, 38.0);
    attentionIcon.SetVAlign(inkEVerticalAlign.Center);
    attentionIcon.SetAtlasResource(r"base\\gameplay\\gui\\fullscreen\\common\\fullscreen_elements.inkatlas");
    attentionIcon.SetTexturePart(n"fluff_attention_fill");
    attentionIcon.SetTintColor(yellow);
    attentionIcon.Reparent(row);

    weightIcon = new inkImage();
    weightIcon.SetName(n"ExamineInteractionInventoryCapacityWeightIcon");
    weightIcon.SetSize(34.0, 34.0);
    weightIcon.SetVAlign(inkEVerticalAlign.Center);
    weightIcon.SetMargin(inkMargin(8.0, 0.0, 16.0, 0.0));
    weightIcon.SetAtlasResource(r"base\\gameplay\\gui\\common\\icons\\atlas_common.inkatlas");
    weightIcon.SetTexturePart(n"icon_weight");
    weightIcon.SetTintColor(yellow);
    weightIcon.Reparent(row);

    warningText = new inkText();
    warningText.SetName(n"ExamineInteractionInventoryCapacityWarningText");
    warningText.SetText(warningValue);
    warningText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    warningText.SetFontStyle(n"Medium");
    warningText.SetFontSize(32);
    warningText.SetTracking(2);
    warningText.SetFitToContent(true);
    warningText.SetVAlign(inkEVerticalAlign.Center);
    warningText.SetTintColor(yellow);
    warningText.Reparent(row);
  }

  private func CreateInspectionInformation() -> Void {
    let body: ref<inkHorizontalPanel>;
    let details: ref<inkVerticalPanel>;
    let description: ref<inkText>;
    let dividerDiagonal: ref<inkRectangle>;
    let dividerRoot: ref<inkCanvas>;
    let dividerVertical: ref<inkRectangle>;
    let dividerHeight: Float;
    let metadata: ref<inkHorizontalPanel>;
    let panel: ref<inkVerticalPanel>;
    let title: ref<inkText>;
    let white = HDRColor(0.92, 0.94, 0.95, 1.0);
    let whiteGlowy = HDRColor(0.92, 0.94, 0.95, 1.25);

    if !this.IsInspectionTextEnabled() {
      return;
    }

    if !IsStringValid(this.m_inspectionTitle) {
      return;
    }

    panel = new inkVerticalPanel();
    panel.SetName(n"ExamineInteractionInformation");
    panel.SetAnchor(inkEAnchor.CenterRight);
    panel.SetAnchorPoint(1.0, 0.5);
    panel.SetHAlign(inkEHorizontalAlign.Right);
    panel.SetVAlign(inkEVerticalAlign.Center);
    panel.SetMargin(inkMargin(0.0, 0.0, 105.0, 0.0));
    panel.SetSize(920.0, 120.0);
    panel.SetFitToContent(true);
    panel.Reparent(this.GetRootCompoundWidget());

    title = new inkText();
    title.SetName(n"ExamineInteractionInformationTitle");
    title.SetText(this.m_inspectionTitle);
    title.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Semi-Bold");
    title.SetFontStyle(n"Semi-Bold");
    title.SetFontSize(92);
    title.SetTracking(2);
    title.SetHorizontalAlignment(textHorizontalAlignment.Left);
    title.SetVerticalAlignment(textVerticalAlignment.Top);
    title.SetHAlign(inkEHorizontalAlign.Left);
    title.SetVAlign(inkEVerticalAlign.Top);
    title.SetSize(900.0, 108.0);
    title.SetFitToContent(true);
    title.SetWrapping(true, 900.0, textWrappingPolicy.Default);
    title.SetLineHeight(0.82);
    title.SetTintColor(whiteGlowy);
    title.Reparent(panel);

    if this.m_worldMeshPreview {
      title.SetHorizontalAlignment(textHorizontalAlignment.Center);
      return;
    }

    if this.m_worldEntityPreview {
      title.SetHorizontalAlignment(textHorizontalAlignment.Center);
      if IsStringValid(this.m_inspectionDescription) {
        description = new inkText();
        description.SetName(n"ExamineInteractionWorldEntityDescription");
        description.SetText(this.m_inspectionDescription);
        description.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
        description.SetFontStyle(n"Medium");
        description.SetFontSize(38);
        description.SetTracking(2);
        description.SetHorizontalAlignment(textHorizontalAlignment.Center);
        description.SetVerticalAlignment(textVerticalAlignment.Top);
        description.SetSize(840.0, 52.0);
        description.SetFitToContent(true);
        description.SetWrapping(true, 840.0, textWrappingPolicy.Default);
        description.SetMargin(inkMargin(30.0, 24.0, 30.0, 0.0));
        description.SetTintColor(white);
        description.SetOpacity(0.7);
        description.Reparent(panel);
      }
      return;
    }

    body = new inkHorizontalPanel();
    body.SetName(n"ExamineInteractionInformationBody");
    body.SetHAlign(inkEHorizontalAlign.Left);
    body.SetVAlign(inkEVerticalAlign.Top);
    body.SetMargin(inkMargin(7.0, 38.0, 0.0, 0.0));
    body.SetSize(880.0, 64.0);
    body.SetFitToContent(true);
    body.Reparent(panel);

    dividerRoot = new inkCanvas();
    dividerRoot.SetName(n"ExamineInteractionInformationDivider");
    dividerRoot.SetHAlign(inkEHorizontalAlign.Left);
    dividerRoot.SetVAlign(inkEVerticalAlign.Fill);
    dividerHeight = 210.0 + Cast<Float>(ArraySize(this.m_actionContext.choices)) * 70.0;
    if IsStringValid(this.m_inspectionDescription) && StrLen(this.m_inspectionDescription) > 42 {
      dividerHeight += Cast<Float>((StrLen(this.m_inspectionDescription) - 1) / 42) * 52.0;
    }
    if this.m_inventoryCapacityWarning {
      dividerHeight += 66.0;
    }
    dividerRoot.SetSize(30.0, dividerHeight + 22.0);
    dividerRoot.Reparent(body);

    dividerDiagonal = new inkRectangle();
    dividerDiagonal.SetName(n"ExamineInteractionInformationDividerKink");
    dividerDiagonal.SetAnchor(inkEAnchor.TopLeft);
    dividerDiagonal.SetAnchorPoint(Vector2(0.5, 0.0));
    dividerDiagonal.SetTranslation(Vector2(8.0, -13.0)); // ;_;
    dividerDiagonal.SetSize(2.0, 42.0);
    dividerDiagonal.SetRotation(-34.0);
    dividerDiagonal.SetTintColor(HDRColor(0.78, 0.82, 0.84, 0.78));
    dividerDiagonal.Reparent(dividerRoot);

    dividerVertical = new inkRectangle();
    dividerVertical.SetName(n"ExamineInteractionInformationDividerStem");
    dividerVertical.SetAnchor(inkEAnchor.TopLeft);
    dividerVertical.SetTranslation(Vector2(18.0, 22.5));
    dividerVertical.SetSize(2.0, dividerHeight);
    dividerVertical.SetTintColor(HDRColor(0.78, 0.82, 0.84, 0.78));
    dividerVertical.Reparent(dividerRoot);

    details = new inkVerticalPanel();
    details.SetName(n"ExamineInteractionInformationDetails");
    details.SetHAlign(inkEHorizontalAlign.Left);
    details.SetVAlign(inkEVerticalAlign.Top);
    details.SetMargin(inkMargin(28.0, 0.0, 0.0, 0.0));
    details.SetSize(850.0, 64.0);
    details.SetFitToContent(true);
    details.Reparent(body);

    metadata = new inkHorizontalPanel();
    metadata.SetName(n"ExamineInteractionInformationMetadata");
    metadata.SetSize(850.0, 64.0);
    metadata.SetHAlign(inkEHorizontalAlign.Left);
    metadata.SetVAlign(inkEVerticalAlign.Top);
    metadata.Reparent(details);

    if IsStringValid(this.m_inspectionType) {
      this.CreateInspectionMetadataLabel(metadata, n"ExamineInteractionInformationType", this.m_inspectionType, white, 0.0);
    }

    if IsStringValid(this.m_inspectionTier) {
      if IsStringValid(this.m_inspectionType) {
        this.CreateInspectionMetadataSeparator(metadata, n"ExamineInteractionInformationTierSeparator");
      }
      this.CreateInspectionMetadataLabel(metadata, n"ExamineInteractionInformationTier", this.m_inspectionTier, this.m_inspectionTierColor, 20.0);
    }

    if IsStringValid(this.m_inspectionPrice) {
      if IsStringValid(this.m_inspectionType) || IsStringValid(this.m_inspectionTier) {
        this.CreateInspectionMetadataSeparator(metadata, n"ExamineInteractionInformationPriceSeparator");
      }
      this.CreateInspectionMetadataLabel(metadata, n"ExamineInteractionInformationPrice", "€$ " + this.m_inspectionPrice, white, 20.0);
    }

    if IsStringValid(this.m_inspectionDescription) {
      description = new inkText();
      description.SetName(n"ExamineInteractionInformationDescription");
      description.SetText(this.m_inspectionDescription);
      description.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
      description.SetFontStyle(n"Medium");
      description.SetFontSize(38);
      description.SetTracking(2);
      description.SetHorizontalAlignment(textHorizontalAlignment.Left);
      description.SetVerticalAlignment(textVerticalAlignment.Top);
      description.SetHAlign(inkEHorizontalAlign.Left);
      description.SetVAlign(inkEVerticalAlign.Top);
      description.SetSize(840.0, 52.0);
      description.SetFitToContent(true);
      description.SetTintColor(white);
      description.SetWrapping(true, 840.0, textWrappingPolicy.Default);
      description.SetOpacity(0.6);
      description.Reparent(details);
    }

    this.CreateInventoryCapacityWarning(details);
    this.CreateInspectionActions(details);
  }

  private func CreateInspectionActionInput(parent: ref<inkHorizontalPanel>, choice: InteractionChoiceData, labelText: String) -> Void {
    let icon: ref<inkImage>;
    let inputController: ref<inkInputDisplayController>;
    let inputData: inkInputKeyData;
    let inputRoot: ref<inkCanvas>;
    let inputText: ref<inkText>;
    let inputWidget: ref<inkCanvas>;
    let label: ref<inkText>;

    inputWidget = new inkCanvas();
    inputWidget.SetSize(64.0, 56.0);
    inputWidget.SetHAlign(inkEHorizontalAlign.Left);
    inputWidget.SetVAlign(inkEVerticalAlign.Center);
    inputWidget.SetMargin(inkMargin(0.0, 0.0, 20.0, 0.0));
    inputWidget.Reparent(parent);

    inputRoot = new inkCanvas();
    inputRoot.SetName(n"inputRoot");
    inputRoot.SetAnchor(inkEAnchor.Centered);
    inputRoot.SetAnchorPoint(Vector2(0.5, 0.5));
    inputRoot.SetSize(56.0, 56.0);
    inputRoot.Reparent(inputWidget);

    icon = new inkImage();
    icon.SetName(n"inputIcon");
    icon.SetAtlasResource(r"base\\gameplay\\gui\\common\\input\\icons_keyboard.inkatlas");
    icon.SetTexturePart(n"kb_escape");
    icon.SetAffectsLayoutWhenHidden(true);
    icon.SetAnchor(inkEAnchor.Centered);
    icon.SetAnchorPoint(Vector2(0.5, 0.5));
    icon.SetSize(56.0, 56.0);
    icon.SetTintColor(HDRColor(0.92, 0.94, 0.95, 1.0));
    icon.Reparent(inputRoot);

    inputText = new inkText();
    inputText.SetName(n"inputText");
    inputText.SetVisible(false);
    inputText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    inputText.SetFontStyle(n"Medium");
    inputText.SetFontSize(36);
    inputText.SetFitToContent(true);
    inputText.SetAnchor(inkEAnchor.Centered);
    inputText.SetAnchorPoint(Vector2(0.5, 0.5));
    inputText.SetTintColor(HDRColor(0.92, 0.94, 0.95, 1.0));
    inputText.Reparent(inputRoot);

    inputController = new inkInputDisplayController();
    inputController.fixedIconHeight = 42;
    inputController.iconRef = inkWidgetRef.Create(icon);
    inputController.nameRef = inkWidgetRef.Create(inputText);
    inputController.canvasRef = inkWidgetRef.Create(inputRoot);
    inputWidget.AttachController(inputController);
    if NotEquals(choice.inputAction, n"") {
      inputController.SetInputAction(choice.inputAction);
    } else {
      inkInputKeyData.SetInputKey(inputData, choice.rawInputKey);
      inkInputKeyData.SetIsHoldInput(inputData, choice.isHoldAction);
      inputController.SetInputKey(inputData);
    }

    label = new inkText();
    label.SetText(labelText);
    label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    label.SetFontStyle(n"Medium");
    label.SetFontSize(42);
    label.SetTracking(2);
    label.SetFitToContent(true);
    label.SetVAlign(inkEVerticalAlign.Center);
    label.SetTintColor(HDRColor(0.92, 0.94, 0.95, 1.0));
    label.Reparent(parent);
  }

  private func CreateInspectionActions(parent: ref<inkVerticalPanel>) -> Void {
    let choice: InteractionChoiceData;
    let i: Int32;
    let labelText: String;
    let row: ref<inkHorizontalPanel>;

    if !IsDefined(this.m_actionContext) {
      return;
    }

    while i < ArraySize(this.m_actionContext.choices) {
      choice = this.m_actionContext.choices[i];
      labelText = GetLocalizedText(choice.localizedName);
      row = new inkHorizontalPanel();
      row.SetName(StringToName(s"ExamineInteractionAction\(i)"));
      row.SetFitToContent(true);
      row.SetHAlign(inkEHorizontalAlign.Left);
      row.SetVAlign(inkEVerticalAlign.Top);
      row.SetMargin(inkMargin(0.0, i == 0 ? 46.0 : 14.0, 0.0, 0.0));
      row.Reparent(parent);
      this.CreateInspectionActionInput(row, choice, IsStringValid(labelText) ? labelText : choice.localizedName);
      i += 1;
    }

    choice.inputAction = n"cancel";
    choice.rawInputKey = EInputKey.IK_None;
    row = new inkHorizontalPanel();
    row.SetName(n"ExamineInteractionActionExit");
    row.SetFitToContent(true);
    row.SetHAlign(inkEHorizontalAlign.Left);
    row.SetVAlign(inkEVerticalAlign.Top);
    row.SetMargin(inkMargin(0.0, ArraySize(this.m_actionContext.choices) > 0 ? 14.0 : 46.0, 0.0, 0.0));
    row.Reparent(parent);
    this.CreateInspectionActionInput(row, choice, "Exit Examine");
  }

  private func IsInspectionTextEnabled() -> Bool {
    let settings = ExamineInteractionSettings.Get(this.GetGame());

    if this.m_worldEntityPreview && this.m_hasAuthoredScannerText {
      return true;
    }

    if !IsDefined(settings) {
      return true;
    }

    switch this.m_inspectionTextCategory {
      case ExamineInspectionTextCategory.Weapon:
        return settings.previewTextWeapons;
      case ExamineInspectionTextCategory.Clothing:
        return settings.previewTextClothing;
      case ExamineInspectionTextCategory.WorldProp:
        return settings.previewTextWorldProps;
    }

    return settings.previewTextLootables;
  }

  private func CreateInspectionHintInput(parent: ref<inkHorizontalPanel>, key: EInputKey, labelText: String, isHold: Bool) -> Void {
    let inputController: ref<inkInputDisplayController>;
    let inputData: inkInputKeyData;
    let inputDisplay: ref<inkHorizontalPanel>;
    let inputIcon: ref<inkImage>;
    let inputRoot: ref<inkCanvas>;
    let inputText: ref<inkText>;
    let label: ref<inkText>;

    inputDisplay = new inkHorizontalPanel();
    inputDisplay.SetFitToContent(true);
    inputDisplay.SetHAlign(inkEHorizontalAlign.Left);
    inputDisplay.SetVAlign(inkEVerticalAlign.Center);
    inputDisplay.SetMargin(inkMargin(0.0, 0.0, 10.0, 0.0));
    inputDisplay.SetSize(38.0, 38.0);
    inputDisplay.Reparent(parent);

    inputRoot = new inkCanvas();
    inputRoot.SetName(n"inputRoot");
    inputRoot.SetHAlign(inkEHorizontalAlign.Left);
    inputRoot.SetVAlign(inkEVerticalAlign.Center);
    inputRoot.SetSize(38.0, 38.0);
    inputRoot.Reparent(inputDisplay);

    inputIcon = new inkImage();
    inputIcon.SetName(n"inputIcon");
    inputIcon.SetAtlasResource(r"base\\gameplay\\gui\\common\\input\\icons_keyboard.inkatlas");
    inputIcon.SetTexturePart(n"kb_escape");
    inputIcon.SetAffectsLayoutWhenHidden(true);
    inputIcon.SetHAlign(inkEHorizontalAlign.Center);
    inputIcon.SetVAlign(inkEVerticalAlign.Center);
    inputIcon.SetAnchor(inkEAnchor.Centered);
    inputIcon.SetAnchorPoint(Vector2(0.5, 0.5));
    inputIcon.SetSize(38.0, 38.0);
    inputIcon.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    inputIcon.BindProperty(n"tintColor", n"MainColors.Blue");
    inputIcon.Reparent(inputRoot);

    inputText = new inkText();
    inputText.SetName(n"inputText");
    inputText.SetVisible(false);
    inputText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    inputText.SetFontStyle(n"Medium");
    inputText.SetFontSize(28);
    inputText.SetFitToContent(true);
    inputText.SetAnchor(inkEAnchor.Centered);
    inputText.SetAnchorPoint(Vector2(0.5, 0.5));
    inputText.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    inputText.BindProperty(n"tintColor", n"MainColors.Blue");
    inputText.Reparent(inputRoot);

    inputController = new inkInputDisplayController();
    inputController.fixedIconHeight = 40;
    inputController.iconRef = inkWidgetRef.Create(inputIcon);
    inputController.nameRef = inkWidgetRef.Create(inputText);
    inputController.canvasRef = inkWidgetRef.Create(inputRoot);
    inputDisplay.AttachController(inputController);

    inkInputKeyData.SetInputKey(inputData, key);
    inkInputKeyData.SetIsHoldInput(inputData, isHold);
    inputController.SetInputKey(inputData);

    label = new inkText();
    label.SetText(labelText);
    label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    label.SetFontStyle(n"Medium");
    label.SetFontSize(28);
    label.SetLetterCase(textLetterCase.UpperCase);
    label.SetHorizontalAlignment(textHorizontalAlignment.Left);
    label.SetVerticalAlignment(textVerticalAlignment.Center);
    label.SetFitToContent(true);
    label.SetVAlign(inkEVerticalAlign.Center);
    label.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    label.BindProperty(n"tintColor", n"MainColors.Blue");
    label.Reparent(parent);
  }

  private func CreateInspectionHintSeparator(parent: ref<inkHorizontalPanel>) -> Void {
    let separator = new inkText();
    separator.SetText("•");
    separator.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    separator.SetFontStyle(n"Medium");
    separator.SetFontSize(28);
    separator.SetFitToContent(true);
    separator.SetVAlign(inkEVerticalAlign.Center);
    separator.SetMargin(inkMargin(26.0, 0.0, 26.0, 0.0));
    separator.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    separator.BindProperty(n"tintColor", n"MainColors.Blue");
    separator.Reparent(parent);
  }

  private func CreateInspectionHints() -> Void {
    let root = this.GetRootCompoundWidget();

    // Keep the complete hint strip behind one strongly-owned root...
    this.m_hintRoot = new inkCanvas();
    this.m_hintRoot.SetName(n"ExamineInteractionHints");
    this.m_hintRoot.SetAnchor(inkEAnchor.BottomCenter);
    this.m_hintRoot.SetAnchorPoint(Vector2(0.5, 1.0));
    this.m_hintRoot.SetHAlign(inkEHorizontalAlign.Center);
    this.m_hintRoot.SetVAlign(inkEVerticalAlign.Bottom);
    this.m_hintRoot.SetMargin(inkMargin(0.0, 0.0, 0.0, 70.0));
    this.m_hintRoot.SetSize(1600.0, 70.0);
    this.m_hintRoot.Reparent(root);

    this.m_keyboardHint = new inkHorizontalPanel();
    this.m_keyboardHint.SetName(n"ExamineInteractionKeyboardHint");
    this.m_keyboardHint.SetAnchor(inkEAnchor.Centered);
    this.m_keyboardHint.SetAnchorPoint(Vector2(0.5, 0.5));
    this.m_keyboardHint.SetHAlign(inkEHorizontalAlign.Center);
    this.m_keyboardHint.SetVAlign(inkEVerticalAlign.Center);
    this.m_keyboardHint.SetSize(1.0, 70.0);
    this.m_keyboardHint.SetFitToContent(true);
    this.m_keyboardHint.Reparent(this.m_hintRoot);
    this.CreateInspectionHintInput(this.m_keyboardHint, EInputKey.IK_LeftMouse, "DRAG TO ROTATE", true);
    this.CreateInspectionHintSeparator(this.m_keyboardHint);
    this.CreateInspectionHintInput(this.m_keyboardHint, EInputKey.IK_MouseWheelUp, "ZOOM", false);
    this.CreateInspectionHintSeparator(this.m_keyboardHint);
    this.CreateInspectionHintInput(this.m_keyboardHint, EInputKey.IK_Escape, "CLOSE", false);

    this.m_controllerHint = new inkHorizontalPanel();
    this.m_controllerHint.SetName(n"ExamineInteractionControllerHint");
    this.m_controllerHint.SetAnchor(inkEAnchor.Centered);
    this.m_controllerHint.SetAnchorPoint(Vector2(0.5, 0.5));
    this.m_controllerHint.SetHAlign(inkEHorizontalAlign.Center);
    this.m_controllerHint.SetVAlign(inkEVerticalAlign.Center);
    this.m_controllerHint.SetSize(1.0, 70.0);
    this.m_controllerHint.SetFitToContent(true);
    this.m_controllerHint.Reparent(this.m_hintRoot);
    this.CreateInspectionHintInput(this.m_controllerHint, EInputKey.IK_Pad_RightAxisX, "ROTATE", false);
    this.CreateInspectionHintSeparator(this.m_controllerHint);
    this.CreateInspectionHintInput(this.m_controllerHint, EInputKey.IK_Pad_LeftAxisY, "ZOOM", false);
    this.CreateInspectionHintSeparator(this.m_controllerHint);
    this.CreateInspectionHintInput(this.m_controllerHint, EInputKey.IK_Pad_B_CIRCLE, "CLOSE", false);

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Inspection hint tree created: popupChildren=\(root.GetNumChildren()) hintChildren=\(this.m_hintRoot.GetNumChildren())");
    this.RefreshInspectionHints(IntEnum<InputDevice>(Cast<Uint8>(GameInstance.GetBlackboardSystem(this.GetGame()).Get(GetAllBlackboardDefs().InputSchemes).GetUint(GetAllBlackboardDefs().InputSchemes.Device))));
  }

  private func RefreshInspectionHints(inputDevice: InputDevice) -> Void {
    let controllerActive = Equals(inputDevice, InputDevice.PAD);

    if IsDefined(this.m_keyboardHint) {
      // Treat unknown/startup values as KBM so the strip can never initialize with both variants hidden
      this.m_keyboardHint.SetVisible(!controllerActive);
    }
    if IsDefined(this.m_controllerHint) {
      this.m_controllerHint.SetVisible(controllerActive);
    }

  }

  private cb func OnExamineInputDeviceChanged(value: Uint32) -> Bool {
    this.RefreshInspectionHints(IntEnum<InputDevice>(Cast<Uint8>(value)));
  }

  protected cb func OnCreate() {
    this.CreateInspectionBackground();
    this.CreateInspectionInformation();
    this.CreateInspectionHints();
  }

  protected cb func OnAttach() {
    let inputBlackboard = GameInstance.GetBlackboardSystem(this.GetGame()).Get(GetAllBlackboardDefs().InputSchemes);

    if IsDefined(inputBlackboard) {
      this.m_inputDeviceCallback = inputBlackboard.RegisterListenerUint(GetAllBlackboardDefs().InputSchemes.Device, this, n"OnExamineInputDeviceChanged");
      this.RefreshInspectionHints(IntEnum<InputDevice>(Cast<Uint8>(inputBlackboard.GetUint(GetAllBlackboardDefs().InputSchemes.Device))));
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Inspection hint tree attached: inWindow=\(inkWidgetHelper.InWindowTree(this.m_hintRoot)) hintChildren=\(this.m_hintRoot.GetNumChildren())");

    this.m_keyInputHandler = GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Input/Key", this, n"OnExamineKeyInput");
    this.m_keyInputHandler
      .AddTarget(InputTarget.Key(EInputKey.IK_LeftMouse, EInputAction.IACT_Press))
      .AddTarget(InputTarget.Key(EInputKey.IK_LeftMouse, EInputAction.IACT_Release));

    this.m_axisInputHandler = GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Input/Axis", this, n"OnExamineAxisInput");
    this.m_axisInputHandler
      .AddTarget(InputTarget.Axis(EInputKey.IK_MouseX))
      .AddTarget(InputTarget.Axis(EInputKey.IK_MouseY))
      .AddTarget(InputTarget.Axis(EInputKey.IK_MouseZ))
      .AddTarget(InputTarget.Axis(EInputKey.IK_MouseWheelUp))
      .AddTarget(InputTarget.Axis(EInputKey.IK_MouseWheelDown))
      .AddTarget(InputTarget.Axis(EInputKey.IK_Pad_LeftAxisY))
      .AddTarget(InputTarget.Axis(EInputKey.IK_Pad_RightAxisX))
      .AddTarget(InputTarget.Axis(EInputKey.IK_Pad_RightAxisY));

    this.RegisterInspectionActionInputs();

    super.OnAttach();
  }

  protected cb func OnDetach() {
    let inputBlackboard = GameInstance.GetBlackboardSystem(this.GetGame()).Get(GetAllBlackboardDefs().InputSchemes);

    if IsDefined(inputBlackboard) && IsDefined(this.m_inputDeviceCallback) {
      inputBlackboard.UnregisterListenerUint(GetAllBlackboardDefs().InputSchemes.Device, this.m_inputDeviceCallback);
      this.m_inputDeviceCallback = null;
    }
    if IsDefined(this.m_keyInputHandler) && this.m_keyInputHandler.IsRegistered() {
      this.m_keyInputHandler.Unregister();
    }
    this.m_keyInputHandler = null;
    if IsDefined(this.m_axisInputHandler) && this.m_axisInputHandler.IsRegistered() {
      this.m_axisInputHandler.Unregister();
    }
    this.m_axisInputHandler = null;
    this.UnregisterInspectionActionInputs();
    this.UnregisterPreviewAttachCallback();
    this.ResetDynamicPreviewFOV();
    this.RestoreSourceVisuals();
    this.RestoreSourceWorldNode();
    this.DespawnPreview();
    super.OnDetach();
  }

  protected cb func OnShow() {
    let uiSystem = GameInstance.GetUISystem(this.GetGame());

    super.OnShow();
    this.HolsterPlayerWeaponForInspection();
    uiSystem.PushGameContext(UIGameContext.ModalPopup);
    this.SpawnPreview();
  }

  private final func HolsterPlayerWeaponForInspection() -> Void {
    let equipmentSystem: wref<EquipmentSystem>;
    let player = GameInstance.GetPlayerSystem(this.GetGame())
      .GetLocalPlayerControlledGameObject() as PlayerPuppet;
    let request: ref<EquipmentSystemWeaponManipulationRequest>;

    if !IsDefined(player) || !IsDefined(GameObject.GetActiveWeapon(player)) {
      return;
    }

    equipmentSystem = GameInstance.GetScriptableSystemsContainer(player.GetGame())
      .Get(n"EquipmentSystem") as EquipmentSystem;
    if !IsDefined(equipmentSystem) {
      return;
    }

    request = new EquipmentSystemWeaponManipulationRequest();
    request.requestType = EquipmentManipulationAction.UnequipWeapon;
    request.owner = player;
    equipmentSystem.QueueRequest(request);
  }

  protected cb func OnHide() {
    let uiSystem = GameInstance.GetUISystem(this.GetGame());

    this.m_dragging = false;
    this.RestoreBorrowedWorldWeapon();
    this.RestoreSourceVisuals();
    this.RestoreSourceWorldNode();
    this.ResetDynamicPreviewFOV();
    this.ResetPreviewDOF();
    uiSystem.PopGameContext(UIGameContext.ModalPopup);
    super.OnHide();
  }

  private cb func OnExamineKeyInput(evt: ref<KeyInputEvent>) -> Void {
    let action = evt.GetAction();
    let choice: InteractionChoiceData;
    let i: Int32;
    let key = evt.GetKey();

    if Equals(key, EInputKey.IK_LeftMouse) {
      if Equals(action, EInputAction.IACT_Press) {
        this.m_dragging = true;
      } else if Equals(action, EInputAction.IACT_Release) {
        this.m_dragging = false;
      }
      return;
    }

    if Equals(action, EInputAction.IACT_Release)
      && !this.m_actionTriggered
      && IsDefined(this.m_actionContext) {
      while i < ArraySize(this.m_actionContext.choices) {
        choice = this.m_actionContext.choices[i];
        if Equals(choice.rawInputKey, key) {
          this.TriggerInspectionAction(i);
          return;
        }
        i += 1;
      }
    }
  }

  private final func RegisterInspectionActionInputs() -> Void {
    let actionName: CName;
    let i: Int32;

    if !IsDefined(this.m_actionPlayer) || !IsDefined(this.m_actionContext) {
      return;
    }

    while i < ArraySize(this.m_actionContext.choices) {
      actionName = this.m_actionContext.choices[i].inputAction;
      if NotEquals(actionName, n"") {
        this.m_actionPlayer.RegisterInputListener(this, actionName);
      }
      if NotEquals(this.m_actionContext.choices[i].rawInputKey, EInputKey.IK_None) {
        this.m_keyInputHandler.AddTarget(InputTarget.Key(
          this.m_actionContext.choices[i].rawInputKey,
          EInputAction.IACT_Release
        ));
      }
      i += 1;
    }
  }

  private final func UnregisterInspectionActionInputs() -> Void {
    let actionName: CName;
    let i: Int32;

    if !IsDefined(this.m_actionPlayer) || !IsDefined(this.m_actionContext) {
      return;
    }

    while i < ArraySize(this.m_actionContext.choices) {
      actionName = this.m_actionContext.choices[i].inputAction;
      if NotEquals(actionName, n"") {
        this.m_actionPlayer.UnregisterInputListener(this, actionName);
      }
      i += 1;
    }
  }

  private final func IsInspectionActionActivated(action: ListenerAction, choice: InteractionChoiceData) -> Bool {
    if choice.isHoldAction {
      return Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_HOLD_COMPLETE);
    }
    return ListenerAction.IsButtonJustReleased(action);
  }

  private final func TriggerInspectionAction(choiceIndex: Int32) -> Bool {
    if this.m_actionTriggered
      || !IsDefined(this.m_actionContext)
      || choiceIndex < 0
      || choiceIndex >= ArraySize(this.m_actionContext.choices) {
      return false;
    }

    this.m_actionTriggered = true;
    if this.TryBeginSodaCanDrinkPresentation(choiceIndex) {
      return true;
    }

    this.FinishInspectionAction(choiceIndex);
    return true;
  }

  public final func FinishInspectionAction(choiceIndex: Int32) -> Void {
    let service: ref<ExamineInteractionService>;

    if !IsDefined(this.m_actionContext)
      || choiceIndex < 0
      || choiceIndex >= ArraySize(this.m_actionContext.choices) {
      this.Close();
      return;
    }

    service = ExamineInteractionService.Get();
    if IsDefined(service) {
      service.RequestInspectionLootAction(this.m_actionContext, choiceIndex);
    }
    this.Close();
  }

  private final func TryBeginSodaCanDrinkPresentation(choiceIndex: Int32) -> Bool {
    let appearanceChanged: Bool;
    let components: array<ref<IComponent>>;
    let i: Int32;
    let meshComponent: ref<MeshComponent>;
    let meshPath: String;
    let preview: ref<Entity>;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();

    if !IsDefined(this.m_actionContext)
      || choiceIndex < 0
      || choiceIndex >= ArraySize(this.m_actionContext.actions)
      || (NotEquals(this.m_actionContext.actions[choiceIndex], n"Drink")
        && NotEquals(this.m_actionContext.actions[choiceIndex], n"Consume"))
      || !IsDefined(staticEntitySystem)
      || !EntityID.IsDefined(this.m_previewEntityID) {
      return false;
    }

    preview = staticEntitySystem.GetEntity(this.m_previewEntityID);
    if !IsDefined(preview) {
      return false;
    }

    components = preview.GetComponents();
    while i < ArraySize(components) {
      meshComponent = components[i] as MeshComponent;
      if IsDefined(meshComponent) {
        meshPath = StrLower(ResRef.ToString(ResourceAsyncRef.GetPath(meshComponent.mesh)));
        if StrFindFirst(meshPath, "soda_can_") >= 0
          && meshComponent.ChangeAppearance(n"open", true) {
          appearanceChanged = true;
          ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Soda-can mesh switched to open appearance: mesh=\(meshPath)");
        }
      }
      i += 1;
    }

    if !appearanceChanged {
      return false;
    }

    GameInstance.GetDelaySystem(this.GetGame()).DelayCallback(
      ExamineInteractionSodaCanDrinkFinish.Create(this, choiceIndex),
      0.55,
      false
    );
    return true;
  }

  protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    let actionName: CName;
    let choice: InteractionChoiceData;
    let i: Int32;

    if this.m_actionTriggered || !IsDefined(this.m_actionContext) {
      return false;
    }

    actionName = ListenerAction.GetName(action);
    while i < ArraySize(this.m_actionContext.choices) {
      choice = this.m_actionContext.choices[i];
      if Equals(choice.inputAction, actionName) {
        if this.IsInspectionActionActivated(action, choice) {
          ListenerActionConsumer.Consume(consumer);
          return this.TriggerInspectionAction(i);
        }
      }
      i += 1;
    }

    return false;
  }

  private final func AccumulatePreviewRotation(pitchDelta: Float, yawDelta: Float) -> Void {
    this.m_pitchOffset += pitchDelta;
    this.m_yawOffset += yawDelta;
  }

  private cb func OnExamineAxisInput(evt: ref<AxisInputEvent>) -> Void {
    let key = evt.GetKey();
    let value = evt.GetValue();

    if Equals(key, EInputKey.IK_MouseX)
      || Equals(key, EInputKey.IK_MouseY) {
      if !this.m_dragging || AbsF(value) < 0.001 {
        return;
      }
      if Equals(key, EInputKey.IK_MouseX) {
        this.AccumulatePreviewRotation(0.0, -value * 0.15);
      } else {
        this.AccumulatePreviewRotation(-value * 0.15, 0.0);
      }
      this.ApplyPreviewTransform();
      this.ApplyDynamicPreviewFOV();
      return;
    }

    if Equals(key, EInputKey.IK_Pad_RightAxisX)
      || Equals(key, EInputKey.IK_Pad_RightAxisY) {
      if AbsF(value) < 0.12 {
        return;
      }
      if Equals(key, EInputKey.IK_Pad_RightAxisX) {
        this.AccumulatePreviewRotation(0.0, -value * 1.50);
      } else {
        this.AccumulatePreviewRotation(-value * 1.50, 0.0);
      }
      this.ApplyPreviewTransform();
      this.ApplyDynamicPreviewFOV();
      return;
    }

    if Equals(key, EInputKey.IK_Pad_LeftAxisY) {
      if AbsF(value) < 0.18 {
        return;
      }
      // Forward on the left stick moves the preview closer, matching a mouse-wheel-up gesture
      this.ChangePreviewDistance(value * -0.018);
      return;
    }

    if Equals(key, EInputKey.IK_MouseWheelUp) {
      this.ChangePreviewDistance(-0.03);
      return;
    }

    if Equals(key, EInputKey.IK_MouseWheelDown) {
      this.ChangePreviewDistance(0.03);
      return;
    }

    if Equals(key, EInputKey.IK_MouseZ) {
      if value > 0.0 {
        this.ChangePreviewDistance(-0.03);
      } else if value < 0.0 {
        this.ChangePreviewDistance(0.03);
      }
      return;
    }

  }

  private cb func OnPreviewAttached(evt: ref<EntityLifecycleEvent>) -> Void {
    let preview = evt.GetEntity();

    if IsDefined(preview)
      && EntityID.IsDefined(this.m_previewEntityID)
      && Equals(preview.GetEntityID(), this.m_previewEntityID) {
      if this.m_worldMeshPreview {
        this.PrepareWorldMeshPreview(preview);
        if !this.ConfigureWorldMeshPreview(preview) {
          FTLog("[ExamineInteraction] World-mesh preview failed: generic mesh component could not be configured.");
          this.Close();
          return;
        }
      }
      this.CopyWorldEntityRuntimeState(preview);
      this.FinalizePreview(preview);
    }
  }

  private final func CopyWorldEntityRuntimeState(preview: ref<Entity>) -> Void {
    let previewFrame: ref<Frame>;
    let sourceFrame: ref<Frame>;

    if !this.m_worldEntityPreview || !IsDefined(preview) || !IsDefined(this.m_sourceEntity) {
      return;
    }

    sourceFrame = this.m_sourceEntity as Frame;
    previewFrame = preview as Frame;
    if IsDefined(sourceFrame) && IsDefined(previewFrame) {
      if sourceFrame.ExamineInteractionCopyPhotoTo(previewFrame) {
        ExamineInteractionLog.Diagnostic("[ExamineInteraction] Live smart-frame screenshot state copied into preview.");
      } else {
        ExamineInteractionLog.Diagnostic("[ExamineInteraction] Smart-frame screenshot state was unavailable for preview.");
      }
    }
  }

  private final func ChangePreviewDistance(delta: Float) -> Void {
    let maxDistance = MaxF(1.50, this.m_framedDistance * 1.75);

    if this.m_environmentHitDistance > 0.0 {
      maxDistance = MinF(maxDistance, this.GetEnvironmentMaxPreviewDistance());
    }
    this.m_distance = ClampF(this.m_distance + delta, 0.20, maxDistance);
    this.ApplyPreviewTransform();
    this.ApplyPreviewDOF();
  }

  private final func ApplyPreviewDOF() -> Void {
    let intensity: Float;
    let zoomRatio: Float;
    let service = GameInstance.GetScriptableServiceContainer()
      .GetService(n"MisterChedda.ExamineInteraction.ExamineInteractionSceneDOF") as ExamineInteractionSceneDOF;

    // The bounds-driven framing distance is our neutral lens position. Moving closer strengthens the separation and pulling back steadily relaxes it so the background does not remain unnaturally smeared at wide framing
    zoomRatio = this.m_distance / MaxF(this.m_framedDistance, 0.20);
    intensity = ClampF(1.25 - zoomRatio * 0.40, 0.25, 1.00);

    if IsDefined(service) {
      service.Apply(this.m_distance, this.m_previewRadius, intensity);
    } else {
      FTLog("[ExamineInteraction] Scene DOF service is unavailable.");
    }
  }

  private final func ResetPreviewDOF() -> Void {
    let service = GameInstance.GetScriptableServiceContainer()
      .GetService(n"MisterChedda.ExamineInteraction.ExamineInteractionSceneDOF") as ExamineInteractionSceneDOF;

    if IsDefined(service) {
      service.Reset();
    } else {
      FTLog("[ExamineInteraction] Hard scene tier reset service is unavailable.");
    }
  }

  private final func GetPreviewCamera() -> ref<FPPCameraComponent> {
    let player = GameInstance.GetPlayerSystem(this.GetGame())
      .GetLocalPlayerControlledGameObject() as PlayerPuppet;

    return IsDefined(player) ? player.GetFPPCameraComponent() : null;
  }

  private final func CalculatePreviewProjectionRadius() -> Float {
    let axis: Vector4;
    let manualOrientation: EulerAngles;
    let projectedHalfHeight: Float;
    let projectedHalfWidth: Float;
    let relativeOrientation: Quaternion;
    let transformedX: Vector4;
    let transformedY: Vector4;
    let transformedZ: Vector4;

    manualOrientation.Pitch = this.m_pitchOffset;
    manualOrientation.Yaw = this.m_yawOffset;
    relativeOrientation = EulerAngles.ToQuat(manualOrientation) * this.m_sourceOrientation;

    axis.X = this.m_previewHalfExtents.X;
    transformedX = Quaternion.Transform(relativeOrientation, axis);
    axis.X = 0.0;
    axis.Y = this.m_previewHalfExtents.Y;
    transformedY = Quaternion.Transform(relativeOrientation, axis);
    axis.Y = 0.0;
    axis.Z = this.m_previewHalfExtents.Z;
    transformedZ = Quaternion.Transform(relativeOrientation, axis);

    // In camera-local space X is horizontal and Z is vertical. The sum of the transformed half-axis projections is the screen-facing AABB
    projectedHalfWidth = AbsF(transformedX.X) + AbsF(transformedY.X) + AbsF(transformedZ.X);
    projectedHalfHeight = AbsF(transformedX.Z) + AbsF(transformedY.Z) + AbsF(transformedZ.Z);
    return SqrtF(projectedHalfWidth * projectedHalfWidth + projectedHalfHeight * projectedHalfHeight);
  }

  private final func CalculatePreviewForwardHalfDepth() -> Float {
    let axis: Vector4;
    let manualOrientation: EulerAngles;
    let relativeOrientation: Quaternion;
    let transformedX: Vector4;
    let transformedY: Vector4;
    let transformedZ: Vector4;

    manualOrientation.Pitch = this.m_pitchOffset;
    manualOrientation.Yaw = this.m_yawOffset;
    relativeOrientation = EulerAngles.ToQuat(manualOrientation) * this.m_sourceOrientation;

    axis.X = this.m_previewHalfExtents.X;
    transformedX = Quaternion.Transform(relativeOrientation, axis);
    axis.X = 0.0;
    axis.Y = this.m_previewHalfExtents.Y;
    transformedY = Quaternion.Transform(relativeOrientation, axis);
    axis.Y = 0.0;
    axis.Z = this.m_previewHalfExtents.Z;
    transformedZ = Quaternion.Transform(relativeOrientation, axis);

    return AbsF(transformedX.Y) + AbsF(transformedY.Y) + AbsF(transformedZ.Y);
  }

  private final func GetEnvironmentMaxPreviewDistance() -> Float {
    if this.m_environmentHitDistance <= 0.0 {
      return MaxF(1.50, this.m_framedDistance * 1.75);
    }

    return MaxF(0.20, this.m_environmentHitDistance - this.CalculatePreviewForwardHalfDepth() - 0.06);
  }

  private final func InitializeDynamicPreviewFOV() -> Void {
    let camera = this.GetPreviewCamera();

    if !IsDefined(camera) || !this.m_hasLocalPivot || this.m_previewRadius <= 0.0 {
      return;
    }

    this.m_previewBaseFov = camera.GetFOV();
    this.m_previewProjectionBaseline = MaxF(this.CalculatePreviewProjectionRadius(), 0.01);
    if this.m_previewBaseFov <= 1.0 || this.m_previewProjectionBaseline <= 0.01 {
      return;
    }

    this.m_previewAppliedFov = this.m_previewBaseFov;
    this.m_previewFovCaptured = true;
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Dynamic preview FOV initialized: base=\(this.m_previewBaseFov) projection=\(this.m_previewProjectionBaseline) radius=\(this.m_previewRadius)");
  }

  private final func ApplyDynamicPreviewFOV() -> Void {
    let amplitude: Float;
    let camera: ref<FPPCameraComponent>;
    let currentProjection: Float;
    let sizeFactor: Float;
    let targetFov: Float;

    if !this.m_previewFovCaptured {
      return;
    }

    camera = this.GetPreviewCamera();
    if !IsDefined(camera) {
      return;
    }

    currentProjection = this.CalculatePreviewProjectionRadius();
    sizeFactor = ClampF((this.m_previewRadius - 0.10) / 0.50, 0.0, 1.0);
    amplitude = 0.40 + sizeFactor * 2.60;
    targetFov = this.m_previewBaseFov + ClampF(
      (currentProjection / this.m_previewProjectionBaseline - 1.0) * amplitude,
      -amplitude,
      amplitude
    );

    // Low-pass each drag sample so the lens breathes instead of snapping..
    this.m_previewAppliedFov += (targetFov - this.m_previewAppliedFov) * 0.22;
    camera.SetFOV(this.m_previewAppliedFov);
  }

  private final func ResetDynamicPreviewFOV() -> Void {
    let camera: ref<FPPCameraComponent>;

    if !this.m_previewFovCaptured {
      return;
    }

    camera = this.GetPreviewCamera();
    if IsDefined(camera) {
      camera.SetFOV(this.m_previewBaseFov);
    }
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Dynamic preview FOV restored: base=\(this.m_previewBaseFov)");
    this.m_previewFovCaptured = false;
  }

  private final func SpawnPreview() -> Void {
    let cameraTransform: Transform;
    let previewID: EntityID;
    let preview: ref<Entity>;
    let previewPosition: Vector4;
    let cameraEuler: EulerAngles;
    let relativeOrientation: EulerAngles;
    let spawnOrientation: Quaternion;
    let spec: ref<StaticEntitySpec>;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();

    if this.m_transactionPreview {
      if !IsDefined(this.m_transactionPreviewEntity) || !IsDefined(this.m_transactionPreviewOwner) {
        FTLog("[ExamineInteraction] Assembled item preview failed: the temporary ItemObject or its drop factory root is unavailable.");
        return;
      }
      if !GameInstance.GetCameraSystem(this.GetGame()).GetActiveCameraWorldTransform(cameraTransform) {
        FTLog("[ExamineInteraction] Assembled item preview failed: active camera transform is unavailable.");
        return;
      }

      this.m_cameraOrientation = Transform.GetOrientation(cameraTransform);
      this.m_previewEntityID = this.m_transactionPreviewOwner.GetEntityID();
      this.ApplyPreviewTransformTo(this.m_transactionPreviewOwner);
      this.FinalizePreview(this.m_transactionPreviewEntity);
      cameraEuler = Quaternion.ToEulerAngles(this.m_cameraOrientation);
      FTLog(s"[ExamineInteraction] Inspection mode opened with engine-assembled item: id=\(EntityID.ToDebugString(this.m_previewEntityID)) appearance=\(NameToString(this.m_transactionPreviewEntity.GetCurrentAppearanceName())) weaponPresentation=\(this.m_assembledWeaponPreview) cameraPitch=\(cameraEuler.Pitch) cameraYaw=\(cameraEuler.Yaw)");
      return;
    }

    if !IsDefined(staticEntitySystem) || !staticEntitySystem.IsReady() {
      FTLog("[ExamineInteraction] Preview spawn failed: StaticEntitySystem is unavailable.");
      return;
    }

    if !ResRef.IsValid(this.m_templatePath) {
      FTLog("[ExamineInteraction] Preview spawn failed: resolved item has no valid template path.");
      return;
    }

    if !GameInstance.GetCameraSystem(this.GetGame()).GetActiveCameraWorldTransform(cameraTransform) {
      FTLog("[ExamineInteraction] Preview spawn failed: active camera transform is unavailable.");
      return;
    }

    previewPosition = Transform.GetPosition(cameraTransform)
      + Transform.GetForward(cameraTransform) * this.m_distance
      + Transform.GetUp(cameraTransform) * 0.02;
    this.m_cameraOrientation = Transform.GetOrientation(cameraTransform);
    cameraEuler = Quaternion.ToEulerAngles(this.m_cameraOrientation);
    if this.m_cameraLocalFacingFlip {
      relativeOrientation.Yaw = 180.0;
      this.m_sourceOrientation = EulerAngles.ToQuat(relativeOrientation);
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] Camera-local entity facing flip applied: yaw=180.000000");
    }
    spawnOrientation = this.m_cameraOrientation * this.m_sourceOrientation;

    spec = new StaticEntitySpec();
    spec.templatePath = this.m_templatePath;
    spec.appearanceName = this.m_appearanceName;
    spec.position = previewPosition;
    spec.orientation = spawnOrientation;
    spec.attached = true;
    ArrayPush(spec.tags, n"MisterCheddaExamineInteractionPreview");

    previewID = staticEntitySystem.SpawnEntity(spec);
    if EntityID.IsDefined(previewID) {
      this.m_previewEntityID = previewID;
      this.RegisterPreviewAttachCallback();
      preview = staticEntitySystem.GetEntity(previewID);
      if IsDefined(preview) {
        if this.m_worldMeshPreview {
          this.PrepareWorldMeshPreview(preview);
          if !this.ConfigureWorldMeshPreview(preview) {
            FTLog("[ExamineInteraction] World-mesh preview is attached but its mesh component could not be configured yet.");
            return;
          }
        }
        this.FinalizePreview(preview);
      }
      FTLog(s"[ExamineInteraction] Inspection mode opened: id=\(EntityID.ToDebugString(previewID)) template=\(ResRef.ToString(spec.templatePath)) appearance=\(NameToString(spec.appearanceName)) cameraPitch=\(cameraEuler.Pitch) cameraYaw=\(cameraEuler.Yaw)");
    } else {
      FTLog("[ExamineInteraction] Preview spawn failed: StaticEntitySystem returned an undefined EntityID.");
    }
  }

  private final func ApplyPreviewTransform() -> Void {
    let preview: ref<Entity>;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();

    if this.m_transactionPreview {
      preview = this.m_transactionPreviewOwner;
    } else if IsDefined(staticEntitySystem) && EntityID.IsDefined(this.m_previewEntityID) {
      preview = staticEntitySystem.GetEntity(this.m_previewEntityID);
    }

    if !IsDefined(preview) {
      return;
    }

    this.ApplyPreviewTransformTo(preview);
    this.ApplyPreviewLightTransform();
  }

  private final func ApplyPreviewTransformTo(preview: ref<Entity>) -> Void {
    let cameraTransform: Transform;
    let manualOrientation: EulerAngles;
    let orientation: Quaternion;
    let previewPosition: Vector4;
    let transform: WorldTransform;

    if !IsDefined(preview)
      || !GameInstance.GetCameraSystem(this.GetGame()).GetActiveCameraWorldTransform(cameraTransform) {
      return;
    }

    previewPosition = Transform.GetPosition(cameraTransform)
      + Transform.GetForward(cameraTransform) * this.m_distance
      + Transform.GetUp(cameraTransform) * 0.02;
    manualOrientation.Pitch = this.m_pitchOffset;
    manualOrientation.Yaw = this.m_yawOffset;
    orientation = this.m_cameraOrientation
      * EulerAngles.ToQuat(manualOrientation)
      * this.m_sourceOrientation;

    if this.m_hasLocalPivot {
      previewPosition -= Quaternion.Transform(orientation, this.m_localPivot);
    }

    transform = preview.GetWorldTransform();
    WorldTransform.SetPosition(transform, previewPosition);
    WorldTransform.SetOrientation(transform, orientation);
    preview.SetWorldTransform(transform);
  }

  private final func FinalizePreview(preview: ref<Entity>) -> Void {
    let entityDistanceScale: Float;
    let entityPath: String;
    let transformRoot: ref<Entity>;

    if this.m_previewReady || !IsDefined(preview) {
      return;
    }

    this.m_previewReady = true;
    this.UnregisterPreviewAttachCallback();
    if !this.m_borrowedWorldWeapon && !this.m_worldMeshPreview {
      this.DisablePreviewCollision(preview);
    }
    if !this.m_previewBoundsPrepared {
      this.ResolvePreviewPivot(preview);
    }
    if this.m_worldEntityPreview {
      entityPath = StrLower(ResRef.ToString(this.m_templatePath));
      if StrFindFirst(entityPath, "\\stash_weapons\\") >= 0 {
        entityDistanceScale = 0.70;
      } else {
        entityDistanceScale = 0.82;
      }
      this.m_distance = ClampF(this.m_distance * entityDistanceScale, 0.26, 1.20);
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Curated entity closer framing applied: scale=\(entityDistanceScale) distance=\(this.m_distance) template=\(entityPath)");
    }
    if this.m_transactionPreview {
      this.ConvertItemPivotToOwnerSpace(preview);
      if this.m_assembledWeaponPreview {
        // Runtime weapon_root bounds vary unpredictably with rigs and attached parts so we start here
        this.m_distance = 0.65;
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Stable assembled-weapon framing applied: distance=0.650000 reportedRadius=\(this.m_previewRadius)");
      }
    }
    this.m_framedDistance = this.m_distance;
    this.InitializeDynamicPreviewFOV();
    this.ApplyPreviewDOF();
    this.SpawnPreviewLight();
    if this.m_transactionPreview && IsDefined(this.m_transactionPreviewOwner) {
      transformRoot = this.m_transactionPreviewOwner;
      if !this.m_borrowedWorldWeapon {
        this.DisablePreviewCollision(transformRoot);
      }
    } else {
      transformRoot = preview;
    }
    this.ApplyPreviewTransformTo(transformRoot);
    if this.m_borrowedWorldWeapon {
      this.SuppressBorrowedWorldWeaponHighlight();
    }
    if !this.m_borrowedWorldWeapon {
      this.HideSourceVisuals();
    }
    if this.m_worldMeshPreview && IsDefined(this.m_sourceWorldNode) && !this.m_worldMeshGrouped {
      this.m_sourceWorldNodeHidden = SetWorldNodeVisible(this.m_sourceWorldNode, false);
      if this.m_sourceWorldNodeHidden {
        ExamineInteractionLog.Diagnostic("[ExamineInteraction] Original streamed prop node hidden for inspection.");
      } else {
        FTLog("[ExamineInteraction] Original streamed prop node could not be hidden.");
      }
    } else if this.m_worldMeshPreview && this.m_worldMeshGrouped {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Grouped source instance intentionally left visible: selection=\(this.m_worldMeshSelectionIndex)/\(this.m_worldMeshSelectionCount)");
    }
    ExamineInteractionLog.Diagnostic("[ExamineInteraction] Preview attached and inspection presentation finalized.");
  }

  private final func ConfigureWorldMeshPreview(preview: ref<Entity>) -> Bool {
    let components: array<ref<IComponent>>;
    let i: Int32;
    let meshComponent: ref<MeshComponent>;

    if !this.m_worldMeshPreview || !IsDefined(preview) || !ResRef.IsValid(this.m_worldMeshPath) {
      return false;
    }

    components = preview.GetComponents();
    while i < ArraySize(components) {
      meshComponent = components[i] as MeshComponent;
      if IsDefined(meshComponent) {
        meshComponent.visualScale = Vector3(this.m_previewScale, this.m_previewScale, this.m_previewScale);
        meshComponent.meshAppearance = this.m_worldMeshAppearance;
        if Equals(meshComponent.meshAppearance, n"") {
          meshComponent.meshAppearance = n"default";
        }
        if meshComponent.ChangeResource(this.m_worldMeshPath, true) {
          ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Direct world mesh loaded into preview: mesh=\(ResRef.ToString(this.m_worldMeshPath)) appearance=\(NameToString(meshComponent.meshAppearance))");
          return true;
        }
      }
      i += 1;
    }

    return false;
  }

  private final func PrepareWorldMeshPreview(preview: ref<Entity>) -> Void {
    if this.m_previewBoundsPrepared || !this.m_worldMeshPreview || !IsDefined(preview) {
      return;
    }

    this.DisablePreviewCollision(preview);
    this.ResolvePreviewPivot(preview);
    this.ResolveWorldMeshEnvironmentFraming();
    this.m_previewBoundsPrepared = true;
  }

  private final func ResolveWorldMeshEnvironmentFraming() -> Void {
    let availableDepth: Float;
    let cameraForward: Vector4;
    let cameraPosition: Vector4;
    let cameraTransform: Transform;
    let desiredDistance: Float;
    let forwardHalfDepth: Float;
    let hitDelta: Vector4;
    let hitDistance: Float;
    let hitPosition: Vector4;
    let minimumDistance: Float = 0.20;
    let minimumScale: Float = 0.20;
    let newDistance: Float;
    let preservedDistance: Float;
    let queryEnd: Vector4;
    let queryStart: Vector4;
    let scale: Float;
    let traceResult: TraceResult;
    let spatialQueries = GameInstance.GetSpatialQueriesSystem(this.GetGame());

    if !this.m_worldMeshPreview
      || !this.m_hasLocalPivot
      || this.m_previewRadius <= 0.0
      || !IsDefined(spatialQueries)
      || !GameInstance.GetCameraSystem(this.GetGame()).GetActiveCameraWorldTransform(cameraTransform) {
      return;
    }

    cameraPosition = Transform.GetPosition(cameraTransform);
    cameraForward = Transform.GetForward(cameraTransform);
    queryStart = cameraPosition + cameraForward * 0.05;
    queryEnd = cameraPosition + cameraForward * 3.0;
    if !spatialQueries.SyncRaycastByCollisionPreset(
      queryStart,
      queryEnd,
      n"World Static",
      traceResult,
      true,
      false
    ) || !TraceResult.IsValid(traceResult) {
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] World-mesh environment framing found no static obstruction ahead.");
      return;
    }

    hitPosition.X = traceResult.position.X;
    hitPosition.Y = traceResult.position.Y;
    hitPosition.Z = traceResult.position.Z;
    hitPosition.W = 1.0;
    hitDelta = hitPosition - cameraPosition;
    hitDistance = hitDelta.X * cameraForward.X
      + hitDelta.Y * cameraForward.Y
      + hitDelta.Z * cameraForward.Z;
    if hitDistance <= 0.08 {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] World-mesh environment framing ignored an invalid near-camera hit: distance=\(hitDistance)");
      return;
    }

    desiredDistance = MaxF(this.m_distance, minimumDistance);
    forwardHalfDepth = this.CalculatePreviewForwardHalfDepth();
    this.m_environmentHitDistance = hitDistance;
    if desiredDistance + forwardHalfDepth + 0.06 <= hitDistance {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] World-mesh environment framing already fits: hit=\(hitDistance) distance=\(desiredDistance) depth=\(forwardHalfDepth)");
      return;
    }

    preservedDistance = (hitDistance - 0.06) / (1.0 + forwardHalfDepth / desiredDistance);
    if preservedDistance >= minimumDistance {
      newDistance = MinF(desiredDistance, preservedDistance);
      scale = ClampF(newDistance / desiredDistance, minimumScale, 1.0);
    } else {
      newDistance = minimumDistance;
      availableDepth = hitDistance - 0.06 - newDistance;
      scale = forwardHalfDepth > 0.001
        ? ClampF(availableDepth / forwardHalfDepth, minimumScale, 1.0)
        : 1.0;
    }

    this.m_previewScale = scale;
    this.m_distance = newDistance;
    this.m_localPivot = this.m_localPivot * scale;
    this.m_previewHalfExtents = this.m_previewHalfExtents * scale;
    this.m_previewRadius *= scale;
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] World-mesh environment framing constrained: hit=\(hitDistance) originalDistance=\(desiredDistance) distance=\(newDistance) originalDepth=\(forwardHalfDepth) scale=\(scale)");
  }

  private final func RestoreSourceWorldNode() -> Void {
    if !this.m_sourceWorldNodeHidden || !IsDefined(this.m_sourceWorldNode) {
      return;
    }

    SetWorldNodeVisible(this.m_sourceWorldNode, true);
    this.m_sourceWorldNodeHidden = false;
    ExamineInteractionLog.Diagnostic("[ExamineInteraction] Original streamed prop node restored after inspection.");
  }

  private final func RegisterPreviewAttachCallback() -> Void {
    let handler: ref<CallbackSystemHandler>;

    this.UnregisterPreviewAttachCallback();
    handler = GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Entity/AfterAttach", this, n"OnPreviewAttached");
    handler.AddTarget(EntityTarget.ID(this.m_previewEntityID));
    this.m_previewAttachCallbackRegistered = true;
  }

  private final func UnregisterPreviewAttachCallback() -> Void {
    if !this.m_previewAttachCallbackRegistered {
      return;
    }

    GameInstance.GetCallbackSystem()
      .UnregisterCallback(n"Entity/AfterAttach", this, n"OnPreviewAttached");
    this.m_previewAttachCallbackRegistered = false;
  }

  private final func ResolvePreviewPivot(preview: ref<Entity>) -> Bool {
    let authoredBounds: Box;
    let boundsMax: Vector4;
    let boundsMin: Vector4;
    let components: array<ref<IComponent>>;
    let corner: Vector4;
    let extentX: Float;
    let extentY: Float;
    let extentZ: Float;
    let framedDistance: Float;
    let hasBounds: Bool;
    let i: Int32;
    let ix: Int32;
    let iy: Int32;
    let iz: Int32;
    let mesh: ref<CMesh>;
    let meshComponent: ref<MeshComponent>;
    let meshPath: ResRef;
    let placedComponent: ref<IPlacedComponent>;
    let pointInRoot: Vector4;
    let radius: Float;
    let recenteredComponents: Int32;
    let skinnedMeshComponent: ref<entSkinnedMeshComponent>;
    let skinnedMeshes: Int32;
    let scale: Vector3;
    let staticMeshes: Int32;
    let token: ref<ResourceToken>;

    if !IsDefined(preview) {
      return false;
    }

    // remember ChangeResource is async and reading meshComponent.meshResource in the same attach callback can expose stale bounds from the placeholder resource. The streamed source node already owns the correct loaded mesh so world prop previews can use its resource-local bounds directly
    if this.m_worldMeshPreview && IsDefined(this.m_sourceWorldNode) {
      authoredBounds = GetWorldNodeLocalBounds(this.m_sourceWorldNode);
      if authoredBounds.Max.X > authoredBounds.Min.X
        && authoredBounds.Max.Y > authoredBounds.Min.Y
        && authoredBounds.Max.Z > authoredBounds.Min.Z {
        boundsMin = authoredBounds.Min;
        boundsMax = authoredBounds.Max;
        hasBounds = true;
        staticMeshes = 1;
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] World prop local bounds resolved from streamed source: min=\(boundsMin.X),\(boundsMin.Y),\(boundsMin.Z) max=\(boundsMax.X),\(boundsMax.Y),\(boundsMax.Z)");
      }
    }

    if !hasBounds {
      components = preview.GetComponents();

      i = 0;
      while i < ArraySize(components) {
      mesh = null;
      meshComponent = components[i] as MeshComponent;
      placedComponent = components[i] as IPlacedComponent;
      skinnedMeshComponent = components[i] as entSkinnedMeshComponent;

      if IsDefined(meshComponent) && meshComponent.IsEnabled() {
        mesh = meshComponent.meshResource;
        scale = meshComponent.visualScale;
        if IsDefined(mesh) {
          staticMeshes += 1;
        }
      } else if IsDefined(skinnedMeshComponent) && skinnedMeshComponent.IsEnabled() {
        meshPath = ResourceAsyncRef.GetPath(skinnedMeshComponent.mesh);
        if ResRef.IsValid(meshPath) {
          token = GameInstance.GetResourceDepot().LoadResource(meshPath);
          if IsDefined(token) {
            mesh = token.GetResource() as CMesh;
          }
        }

        scale.X = 1.0;
        scale.Y = 1.0;
        scale.Z = 1.0;
        if IsDefined(mesh) {
          skinnedMeshes += 1;
        } else {
          ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Skinned preview mesh bounds unavailable: component=\(NameToString(components[i].GetName())) resource=\(ResRef.ToString(meshPath))");
        }
      }

      if IsDefined(mesh) && IsDefined(placedComponent) {
          ix = 0;
          while ix < 2 {
            iy = 0;
            while iy < 2 {
              iz = 0;
              while iz < 2 {
                corner.X = ix == 0 ? mesh.boundingBox.Min.X : mesh.boundingBox.Max.X;
                corner.Y = iy == 0 ? mesh.boundingBox.Min.Y : mesh.boundingBox.Max.Y;
                corner.Z = iz == 0 ? mesh.boundingBox.Min.Z : mesh.boundingBox.Max.Z;
                corner.W = 1.0;
                corner.X *= scale.X;
                corner.Y *= scale.Y;
                corner.Z *= scale.Z;

                pointInRoot = placedComponent.GetLocalPosition()
                  + Quaternion.Transform(placedComponent.GetLocalOrientation(), corner);
                pointInRoot.W = 0.0;

                if !hasBounds {
                  boundsMin = pointInRoot;
                  boundsMax = pointInRoot;
                  hasBounds = true;
                } else {
                  boundsMin.X = MinF(boundsMin.X, pointInRoot.X);
                  boundsMin.Y = MinF(boundsMin.Y, pointInRoot.Y);
                  boundsMin.Z = MinF(boundsMin.Z, pointInRoot.Z);
                  boundsMax.X = MaxF(boundsMax.X, pointInRoot.X);
                  boundsMax.Y = MaxF(boundsMax.Y, pointInRoot.Y);
                  boundsMax.Z = MaxF(boundsMax.Z, pointInRoot.Z);
                }
                iz += 1;
              }
              iy += 1;
            }
            ix += 1;
          }
      }
        i += 1;
      }
    }

    if !hasBounds {
      this.m_hasLocalPivot = false;
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] Preview pivot fallback: no loaded static or skinned mesh bounds were available.");
      return false;
    }

    this.m_localPivot = (boundsMin + boundsMax) * 0.5;
    this.m_localPivot.W = 0.0;
    this.m_hasLocalPivot = true;

    // account for some wonky bounds
    if this.m_worldMeshPreview
      && (AbsF(this.m_localPivot.X) > 10.0
        || AbsF(this.m_localPivot.Y) > 10.0
        || AbsF(this.m_localPivot.Z) > 10.0) {
      if ArraySize(components) == 0 {
        components = preview.GetComponents();
      }
      i = 0;
      while i < ArraySize(components) {
        meshComponent = components[i] as MeshComponent;
        placedComponent = components[i] as IPlacedComponent;
        if IsDefined(meshComponent) && IsDefined(placedComponent) {
          pointInRoot = placedComponent.GetLocalPosition() - this.m_localPivot;
          pointInRoot.W = 0.0;
          placedComponent.SetLocalPosition(pointInRoot);
          recenteredComponents += 1;
        }
        i += 1;
      }
      if recenteredComponents > 0 {
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Baked world-offset preview mesh recentered locally: x=\(this.m_localPivot.X) y=\(this.m_localPivot.Y) z=\(this.m_localPivot.Z) components=\(recenteredComponents)");
        this.m_localPivot.X = 0.0;
        this.m_localPivot.Y = 0.0;
        this.m_localPivot.Z = 0.0;
      }
    }

    extentX = boundsMax.X - boundsMin.X;
    extentY = boundsMax.Y - boundsMin.Y;
    extentZ = boundsMax.Z - boundsMin.Z;
    this.m_previewHalfExtents.X = extentX * 0.5;
    this.m_previewHalfExtents.Y = extentY * 0.5;
    this.m_previewHalfExtents.Z = extentZ * 0.5;
    this.m_previewHalfExtents.W = 0.0;
    radius = SqrtF(extentX * extentX + extentY * extentY + extentZ * extentZ) * 0.5;
    this.m_previewRadius = radius;
    framedDistance = ClampF(radius * 1.8, 0.30, 1.20);
    this.m_distance = framedDistance;

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Preview pivot/framing resolved: x=\(this.m_localPivot.X) y=\(this.m_localPivot.Y) z=\(this.m_localPivot.Z) extents=\(extentX),\(extentY),\(extentZ) radius=\(radius) distance=\(this.m_distance) staticMeshes=\(staticMeshes) skinnedMeshes=\(skinnedMeshes)");
    return true;
  }

  private final func ConvertItemPivotToOwnerSpace(preview: ref<Entity>) -> Void {
    let centerInOwner: WorldPosition;
    let centerInWorld: WorldPosition;
    let ownerInverse: WorldTransform;

    if !this.m_transactionPreview
      || !this.m_hasLocalPivot
      || !IsDefined(preview)
      || !IsDefined(this.m_transactionPreviewOwner) {
      return;
    }

    centerInWorld = WorldTransform.TransformPoint(preview.GetWorldTransform(), this.m_localPivot);
    ownerInverse = WorldTransform.GetInverse(this.m_transactionPreviewOwner.GetWorldTransform());
    centerInOwner = WorldTransform.TransformPoint(ownerInverse, WorldPosition.ToVector4(centerInWorld));
    this.m_localPivot = WorldPosition.ToVector4(centerInOwner);
    this.m_localPivot.W = 0.0;

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Assembled item pivot converted to drop-wrapper space: x=\(this.m_localPivot.X) y=\(this.m_localPivot.Y) z=\(this.m_localPivot.Z)");
  }

  private final func SpawnPreviewLight() -> Void {
    let appliedIntensity: Float;
    let components: array<ref<IComponent>>;
    let i: Int32;
    let light: ref<Entity>;
    let lightComponent: ref<gameLightComponent>;
    let lightID: EntityID;
    let lightDepth: Float;
    let lightHeight: Float;
    let lightDirection: Vector4;
    let lightPosition: Vector4;
    let previewRadius: Float;
    let spec: ref<StaticEntitySpec>;
    let targetPosition: Vector4;
    let cameraTransform: Transform;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();
    let settings = ExamineInteractionSettings.Get(this.GetGame());

    if IsDefined(settings) && !settings.previewLightEnabled {
      return;
    }

    if !IsDefined(staticEntitySystem)
      || !staticEntitySystem.IsReady()
      || !GameInstance.GetCameraSystem(this.GetGame()).GetActiveCameraWorldTransform(cameraTransform) {
      FTLog("[ExamineInteraction] Preview spotlight spawn failed: entity or camera system is unavailable.");
      return;
    }

    previewRadius = this.m_assembledWeaponPreview ? 0.20 : MaxF(this.m_previewRadius, 0.20);
    lightDepth = ClampF(previewRadius * 1.20, 0.28, 0.80);
    lightHeight = ClampF(previewRadius * 0.75, 0.18, 0.50);

    lightPosition = Transform.GetPosition(cameraTransform)
      + Transform.GetForward(cameraTransform) * (this.m_distance - lightDepth)
      + Transform.GetUp(cameraTransform) * (lightHeight - 0.04);
    targetPosition = Transform.GetPosition(cameraTransform)
      + Transform.GetForward(cameraTransform) * this.m_distance
      - Transform.GetUp(cameraTransform) * 0.04;
    lightDirection = targetPosition - lightPosition;
    lightDirection.W = 0.0;

    spec = new StaticEntitySpec();
    spec.templatePath = r"misterchedda\\examine_interaction\\entities\\examine_preview_light.ent";
    spec.position = lightPosition;
    spec.orientation = Quaternion.BuildFromDirectionVector(lightDirection, Transform.GetUp(cameraTransform));
    spec.attached = true;
    ArrayPush(spec.tags, n"MisterCheddaExamineInteractionPreview");
    ArrayPush(spec.tags, n"MisterCheddaExamineInteractionPreviewLight");

    lightID = staticEntitySystem.SpawnEntity(spec);
    if !EntityID.IsDefined(lightID) {
      FTLog("[ExamineInteraction] Preview spotlight spawn failed: StaticEntitySystem returned an undefined EntityID.");
      return;
    }

    this.m_previewLightEntityID = lightID;
    appliedIntensity = 350.0 * (IsDefined(settings) ? settings.previewLightIntensity : 1.0);
    light = staticEntitySystem.GetEntity(lightID);
    if IsDefined(light) {
      components = light.GetComponents();
      while i < ArraySize(components) {
        lightComponent = components[i] as gameLightComponent;
        if IsDefined(lightComponent) {
          lightComponent.SetIntensity(appliedIntensity, 0.0);
          break;
        }
        i += 1;
      }
    }
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Authored preview spotlight spawned: id=\(EntityID.ToDebugString(lightID)) depth=\(lightDepth) height=\(lightHeight) intensity=\(appliedIntensity)");
  }

  private final func ApplyPreviewLightTransform() -> Void {
    let cameraTransform: Transform;
    let light: ref<Entity>;
    let lightDepth: Float;
    let lightHeight: Float;
    let lightDirection: Vector4;
    let lightPosition: Vector4;
    let previewRadius: Float;
    let targetPosition: Vector4;
    let transform: WorldTransform;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();

    if !IsDefined(staticEntitySystem)
      || !EntityID.IsDefined(this.m_previewLightEntityID)
      || !GameInstance.GetCameraSystem(this.GetGame()).GetActiveCameraWorldTransform(cameraTransform) {
      return;
    }

    light = staticEntitySystem.GetEntity(this.m_previewLightEntityID);
    if !IsDefined(light) {
      return;
    }

    previewRadius = this.m_assembledWeaponPreview ? 0.20 : MaxF(this.m_previewRadius, 0.20);
    lightDepth = ClampF(previewRadius * 1.20, 0.28, 0.80);
    lightHeight = ClampF(previewRadius * 0.75, 0.18, 0.50);
    lightPosition = Transform.GetPosition(cameraTransform)
      + Transform.GetForward(cameraTransform) * (this.m_distance - lightDepth)
      + Transform.GetUp(cameraTransform) * (lightHeight - 0.04);
    targetPosition = Transform.GetPosition(cameraTransform)
      + Transform.GetForward(cameraTransform) * this.m_distance
      - Transform.GetUp(cameraTransform) * 0.04;
    lightDirection = targetPosition - lightPosition;
    lightDirection.W = 0.0;

    transform = light.GetWorldTransform();
    WorldTransform.SetPosition(transform, lightPosition);
    WorldTransform.SetOrientation(transform, Quaternion.BuildFromDirectionVector(lightDirection, Transform.GetUp(cameraTransform)));
    light.SetWorldTransform(transform);
  }

  private final func DisablePreviewCollision(preview: ref<Entity>) -> Void {
    let collider: ref<ColliderComponent>;
    let components: array<ref<IComponent>>;
    let disabled: Int32;
    let i: Int32;
    let physicalMesh: ref<PhysicalMeshComponent>;
    let simpleCollider: ref<SimpleColliderComponent>;

    if !IsDefined(preview) {
      return;
    }

    components = preview.GetComponents();
    i = 0;
    while i < ArraySize(components) {
      physicalMesh = components[i] as PhysicalMeshComponent;
      collider = components[i] as ColliderComponent;
      simpleCollider = components[i] as SimpleColliderComponent;

      if IsDefined(physicalMesh) {
        physicalMesh.filterData = new physicsFilterData();
        physicalMesh.ToggleCollision(false);
        disabled += 1;
      } else if IsDefined(collider) && collider.IsEnabled() {
        collider.Toggle(false);
        disabled += 1;
      } else if IsDefined(simpleCollider) && simpleCollider.IsEnabled() {
        simpleCollider.Toggle(false);
        disabled += 1;
      } else if (components[i].IsA(n"gameStaticAreaShapeComponent")
          || components[i].IsA(n"entDynamicActorRepellingComponent"))
        && components[i].IsEnabled() {
        components[i].Toggle(false);
        disabled += 1;
      }
      i += 1;
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Preview collision disabled: components=\(disabled)");
  }

  private final func HideSourceVisuals() -> Void {
    let components: array<ref<IComponent>>;
    let i: Int32;
    let visual: ref<IVisualComponent>;

    if this.m_sourceVisualsHidden || !IsDefined(this.m_sourceEntity) {
      return;
    }

    ArrayClear(this.m_hiddenSourceVisuals);
    components = this.m_sourceEntity.GetComponents();
    i = 0;
    while i < ArraySize(components) {
      visual = components[i] as IVisualComponent;
      if IsDefined(visual) && visual.IsEnabled() {
        ArrayPush(this.m_hiddenSourceVisuals, visual.GetName());
        visual.TemporaryHide(true);
      }
      i += 1;
    }

    this.m_sourceVisualsHidden = ArraySize(this.m_hiddenSourceVisuals) > 0;
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Original item visuals hidden: count=\(ArraySize(this.m_hiddenSourceVisuals))");
  }

  private final func RestoreSourceVisuals() -> Void {
    let component: ref<IComponent>;
    let i: Int32;
    let visual: ref<IVisualComponent>;

    if !this.m_sourceVisualsHidden {
      return;
    }

    if IsDefined(this.m_sourceEntity) {
      i = 0;
      while i < ArraySize(this.m_hiddenSourceVisuals) {
        component = this.m_sourceEntity.FindComponentByName(this.m_hiddenSourceVisuals[i]);
        visual = component as IVisualComponent;
        if IsDefined(visual) {
          visual.TemporaryHide(false);
        }
        i += 1;
      }
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Original item visuals restored: count=\(ArraySize(this.m_hiddenSourceVisuals))");
    ArrayClear(this.m_hiddenSourceVisuals);
    this.m_sourceVisualsHidden = false;
  }

  private final func SuppressBorrowedWorldWeaponHighlight() -> Void {
    let preview: ref<ItemObject>;
    let visionModeSystem: ref<VisionModeSystem>;

    if !this.m_borrowedWorldWeapon || !IsDefined(this.m_transactionPreviewEntity) {
      return;
    }

    preview = this.m_transactionPreviewEntity;
    visionModeSystem = GameInstance.GetVisionModeSystem(preview.GetGame());
    if IsDefined(visionModeSystem) {
      visionModeSystem.CancelForceVisionAppearance(preview, 0.0);
      this.m_borrowedWeaponHighlightSuppressed = true;
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] Borrowed weapon loot outline suppressed for inspection.");
    }
  }

  private final func RestoreBorrowedWorldWeaponHighlight() -> Void {
    let reactivateEvent: ref<ForceReactivateHighlightsEvent>;

    if !this.m_borrowedWeaponHighlightSuppressed || !IsDefined(this.m_transactionPreviewEntity) {
      return;
    }

    reactivateEvent = new ForceReactivateHighlightsEvent();
    this.m_transactionPreviewEntity.QueueEvent(reactivateEvent);
    this.m_borrowedWeaponHighlightSuppressed = false;
    ExamineInteractionLog.Diagnostic("[ExamineInteraction] Borrowed weapon highlight stack reactivated after inspection.");
  }

  private final func RestoreBorrowedWorldWeapon() -> Void {
    if !this.m_borrowedWorldWeapon || !IsDefined(this.m_transactionPreviewOwner) {
      return;
    }

    this.m_transactionPreviewOwner.SetWorldTransform(this.m_borrowedWorldTransform);
    this.RestoreBorrowedWorldWeaponHighlight();
    this.m_borrowedWorldWeapon = false;
    ExamineInteractionLog.Diagnostic("[ExamineInteraction] Borrowed ground weapon restored to its original world transform.");
  }

  private final func DespawnPreview() -> Void {
    let emptyID: EntityID;
    let staticEntitySystem = GameInstance.GetStaticEntitySystem();

    if IsDefined(staticEntitySystem) {
      staticEntitySystem.DespawnTagged(n"MisterCheddaExamineInteractionPreview");
    }
    if this.m_transactionPreview && IsDefined(this.m_transactionPreviewOwner) {
      if this.m_borrowedWorldWeapon {
        this.RestoreBorrowedWorldWeapon();
      } else if IsDefined(this.m_itemPreviewFactory) {
        this.m_itemPreviewFactory.ReleasePreview();
      }
      this.m_itemPreviewFactory = null;
      this.m_transactionPreviewEntity = null;
      this.m_transactionPreviewOwner = null;
      this.m_transactionPreview = false;
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] Transaction-backed item preview released.");
    }
    this.UnregisterPreviewAttachCallback();
    this.m_previewEntityID = emptyID;
    this.m_previewLightEntityID = emptyID;
    this.m_previewReady = false;
    this.m_hasLocalPivot = false;
    this.m_previewHalfExtents.X = 0.0;
    this.m_previewHalfExtents.Y = 0.0;
    this.m_previewHalfExtents.Z = 0.0;
    this.m_previewRadius = 0.0;
    this.m_previewScale = 1.0;
    this.m_framedDistance = 0.0;
    this.m_environmentHitDistance = 0.0;
    this.m_previewBoundsPrepared = false;
    FTLog("[ExamineInteraction] Inspection mode closed and preview despawned.");
  }
}

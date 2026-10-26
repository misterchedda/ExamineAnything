module MisterChedda.ExamineInteraction

public abstract class ExamineInteractionGenericItemFactory {
  public static func ResolveTemplate(entityName: CName) -> ResRef {
    let empty: ResRef;

    if Equals(entityName, n"base_junk_item") {
      return r"base\\gameplay\\items\\misc\\base_junk_item.ent";
    }
    if Equals(entityName, n"money") {
      return r"base\\gameplay\\items\\misc\\base_money_item.ent";
    }
    if Equals(entityName, n"base_food_item") {
      return r"base\\gameplay\\items\\consumables\\food\\base_food_item.ent";
    }
    if Equals(entityName, n"base_drink_item") {
      return r"base\\gameplay\\items\\consumables\\drinks\\base_drink_item.ent";
    }
    if Equals(entityName, n"base_alcohol_item") {
      return r"base\\gameplay\\items\\consumables\\alcohol\\base_alcohol_item.ent";
    }

    return empty;
  }

  public static func ResolveAppearance(template: ref<entEntityTemplate>, requestedAppearance: CName) -> CName {
    let appearances: array<entTemplateAppearance>;
    let i: Int32;

    if !IsDefined(template) {
      return n"";
    }

    appearances = template.appearances;
    if NotEquals(requestedAppearance, n"")
      && NotEquals(requestedAppearance, n"None") {
      i = 0;
      while i < ArraySize(appearances) {
        if Equals(appearances[i].name, requestedAppearance) {
          return requestedAppearance;
        }
        i += 1;
      }
    }

    i = 0;
    while i < ArraySize(appearances) {
      if Equals(appearances[i].name, n"default") {
        return n"default";
      }
      i += 1;
    }

    // Some simple item roots author their mesh directly on the entity rather than through an appearance resource. Spawning their default appearance is valid even though the template appearance array is empty
    if ArraySize(appearances) == 0 {
      return n"default";
    }

    return n"";
  }

  public static func CanResolve(itemRecord: wref<Item_Record>) -> Bool {
    let templatePath: ResRef;

    if !IsDefined(itemRecord) {
      return false;
    }

    templatePath = ExamineInteractionGenericItemFactory.ResolveTemplate(itemRecord.EntityName());
    return ResRef.IsValid(templatePath)
      && GameInstance.GetResourceDepot().ResourceExists(templatePath);
  }
}

public abstract class ExamineInteractionClothingFactory {
  private static func HasGeneratedAppearanceIcon(itemID: ItemID, baseAppearance: CName, gender: CName) -> Bool {
    let iconName: CName;
    let iconNameText: String;
    let iconRecord: wref<UIIcon_Record>;

    if !ItemID.IsValid(itemID) {
      return false;
    }

    iconName = IconsNameResolver.GetIconsNameResolver().TranslateItemToIconName(
      ItemID.GetTDBID(itemID),
      Equals(gender, n"Male")
    );
    if Equals(iconName, n"") || Equals(iconName, n"None") {
      return false;
    }

    iconNameText = NameToString(iconName);
    if StrFindFirst(StrLower(iconNameText), StrLower(NameToString(baseAppearance))) < 0
      || StrFindFirst(StrLower(iconNameText), StrLower(NameToString(gender))) < 0
      || StrFindFirst(StrLower(iconNameText), "tpp") < 0 {
      return false;
    }

    iconRecord = TweakDBInterface.GetUIIconRecord(
      TDBID.Create("UIIcon." + iconNameText)
    );
    if IsDefined(iconRecord) {
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Clothing external-appearance icon validated: item=\(TDBID.ToStringDEBUG(ItemID.GetTDBID(itemID))) base=\(NameToString(baseAppearance)) gender=\(NameToString(gender)) icon=\(iconNameText)");
    }
    return IsDefined(iconRecord);
  }

  public static func ResolveBaseAppearance(itemRecord: wref<Item_Record>, itemID: ItemID, gender: CName) -> CName {
    let maleAppearance: CName;

    if !IsDefined(itemRecord) {
      return n"";
    }

    if Equals(gender, n"Male") {
      maleAppearance = TweakDBInterface.GetCName(
        ItemID.GetTDBID(itemID) + t".appearanceNameMale",
        n""
      );
      if NotEquals(maleAppearance, n"") && NotEquals(maleAppearance, n"None") {
        return maleAppearance;
      }
    }

    return itemRecord.AppearanceName();
  }

  private static func ResolveTemplateAppearance(template: ref<entEntityTemplate>, candidate: CName, visited: array<ref<entEntityTemplate>>) -> CName {
    let appearances: array<entTemplateAppearance>;
    let i: Int32;
    let includeReference: ResourceRef;
    let includeTemplate: ref<entEntityTemplate>;
    let includes: array<entTemplateInclude>;
    let resolved: CName;

    if !IsDefined(template) || ArrayContains(visited, template) {
      return n"";
    }

    ArrayPush(visited, template);
    appearances = template.appearances;
    while i < ArraySize(appearances) {
      if Equals(appearances[i].name, candidate) {
        return appearances[i].name;
      }
      if Equals(appearances[i].appearanceName, candidate) {
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Clothing external appearance mapped to entity selector: candidate=\(NameToString(candidate)) selector=\(NameToString(appearances[i].name)) resource=\(ResRef.ToString(ResourceAsyncRef.GetPath(appearances[i].appearanceResource)))");
        return appearances[i].name;
      }
      i += 1;
    }

    includes = template.includes;
    i = 0;
    while i < ArraySize(includes) {
      includeReference = ResourceRef.FromPath(ResourceAsyncRef.GetPath(includes[i].template));
      if ResourceRef.IsLoaded(includeReference) {
        includeTemplate = ResourceRef.GetResource(includeReference) as entEntityTemplate;
        resolved = ExamineInteractionClothingFactory.ResolveTemplateAppearance(includeTemplate, candidate, visited);
        if NotEquals(resolved, n"") {
          return resolved;
        }
      }
      i += 1;
    }

    return n"";
  }

  private static func LogExternalAppearanceMappings(template: ref<entEntityTemplate>, baseAppearance: CName) -> Void {
    let includeResource: ResourceRef;
    let appearances: array<entTemplateAppearance>;
    let baseText = StrLower(NameToString(baseAppearance));
    let i: Int32;
    let includes: array<entTemplateInclude>;
    let mappedText: String;
    let selectorText: String;

    if !IsDefined(template) {
      return;
    }

    appearances = template.appearances;
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Clothing external-appearance mapping probe: rootEntries=\(ArraySize(appearances)) includes=\(ArraySize(template.includes)) base=\(NameToString(baseAppearance))");
    while i < ArraySize(appearances) {
      selectorText = NameToString(appearances[i].name);
      mappedText = NameToString(appearances[i].appearanceName);
      if StrFindFirst(StrLower(selectorText), baseText) >= 0
        || StrFindFirst(StrLower(mappedText), baseText) >= 0 {
        ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Clothing appearance entry probe: selector=\(selectorText) mapped=\(mappedText) resource=\(ResRef.ToString(ResourceAsyncRef.GetPath(appearances[i].appearanceResource)))");
      }
      i += 1;
    }

    includes = template.includes;
    i = 0;
    while i < ArraySize(includes) {
      includeResource = ResourceRef.FromPath(ResourceAsyncRef.GetPath(includes[i].template));
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Clothing appearance include probe: path=\(ResRef.ToString(ResourceAsyncRef.GetPath(includes[i].template))) loaded=\(ResourceRef.IsLoaded(includeResource))");
      i += 1;
    }
  }

  public static func ResolveTemplate(entityName: CName) -> ResRef {
    let empty: ResRef;

    if Equals(entityName, n"player_underwear_item") {
      return r"base\\gameplay\\items\\equipment\\underwear\\player_underwear_item.ent";
    }
    if Equals(entityName, n"player_inner_torso_item") {
      return r"base\\gameplay\\items\\equipment\\torso\\player_inner_torso_item.ent";
    }
    if Equals(entityName, n"player_outer_torso_item") {
      return r"base\\gameplay\\items\\equipment\\torso\\player_outer_torso_item.ent";
    }
    if Equals(entityName, n"player_face_item") {
      return r"base\\gameplay\\items\\equipment\\face\\player_face_item.ent";
    }
    if Equals(entityName, n"player_head_item") {
      return r"base\\gameplay\\items\\equipment\\hat\\player_head_item.ent";
    }
    if Equals(entityName, n"player_legs_item") {
      return r"base\\gameplay\\items\\equipment\\legs\\player_legs_item.ent";
    }
    if Equals(entityName, n"player_feet_item") {
      return r"base\\gameplay\\items\\equipment\\feet\\player_feet_item.ent";
    }
    if Equals(entityName, n"player_outfit_item") {
      return r"base\\gameplay\\items\\equipment\\outfit\\player_outfit_item.ent";
    }
    if Equals(entityName, n"player_underwear_top_item") {
      return r"base\\gameplay\\items\\equipment\\underwear\\player_underwear_top_item.ent";
    }
    if Equals(entityName, n"player_underwear_bottom_item") {
      return r"base\\gameplay\\items\\equipment\\underwear\\player_underwear_bottom_item.ent";
    }
    if Equals(entityName, n"player_face_item_ep1") {
      return r"ep1\\gameplay\\items\\equipment\\face\\player_face_item_ep1.ent";
    }
    if Equals(entityName, n"player_head_item_ep1") {
      return r"ep1\\gameplay\\items\\equipment\\hat\\player_head_item_ep1.ent";
    }
    if Equals(entityName, n"player_inner_torso_item_ep1") {
      return r"ep1\\gameplay\\items\\equipment\\torso\\player_inner_torso_item_ep1.ent";
    }
    if Equals(entityName, n"player_outer_torso_item_ep1") {
      return r"ep1\\gameplay\\items\\equipment\\torso\\player_outer_torso_item_ep1.ent";
    }
    if Equals(entityName, n"player_legs_item_ep1") {
      return r"ep1\\gameplay\\items\\equipment\\legs\\player_legs_item_ep1.ent";
    }
    if Equals(entityName, n"player_feet_item_ep1") {
      return r"ep1\\gameplay\\items\\equipment\\feet\\player_feet_item_ep1.ent";
    }

    return empty;
  }

  public static func ResolveAppearance(template: ref<entEntityTemplate>, baseAppearance: CName, gender: CName, itemID: ItemID) -> CName {
    let candidatePlain: CName;
    let candidateTPP: CName;
    let candidateTPPFull: CName;
    let candidateTPPPart: CName;
    let resolved: CName;
    let visitedPlain: array<ref<entEntityTemplate>>;
    let visitedTPP: array<ref<entEntityTemplate>>;
    let visitedTPPFull: array<ref<entEntityTemplate>>;
    let visitedTPPPart: array<ref<entEntityTemplate>>;

    if !IsDefined(template)
      || Equals(baseAppearance, n"")
      || Equals(gender, n"") {
      return n"";
    }

    candidateTPP = StringToName(s"\(NameToString(baseAppearance))&\(NameToString(gender))&TPP");
    candidateTPPFull = StringToName(s"\(NameToString(baseAppearance))&\(NameToString(gender))&TPP&Full");
    candidateTPPPart = StringToName(s"\(NameToString(baseAppearance))&\(NameToString(gender))&TPP&Part");
    candidatePlain = StringToName(s"\(NameToString(baseAppearance))&\(NameToString(gender))");

    // TPP is authoritative when the factory exposes it (outer torso, outfits, and similar assets). Simpler factories such as many inner-torso items expose only the gender qualified key
    resolved = ExamineInteractionClothingFactory.ResolveTemplateAppearance(template, candidateTPP, visitedTPP);
    if NotEquals(resolved, n"") {
      return resolved;
    }

    resolved = ExamineInteractionClothingFactory.ResolveTemplateAppearance(template, candidateTPPFull, visitedTPPFull);
    if NotEquals(resolved, n"") {
      return resolved;
    }

    resolved = ExamineInteractionClothingFactory.ResolveTemplateAppearance(template, candidatePlain, visitedPlain);
    if NotEquals(resolved, n"") {
      return resolved;
    }

    resolved = ExamineInteractionClothingFactory.ResolveTemplateAppearance(template, candidateTPPPart, visitedTPPPart);
    if NotEquals(resolved, n"") {
      return resolved;
    }

    // Generated clothing icons are authored from the same entity and TPP appearance pair, so they validate appearances stored in external resources that the root template array does not expose
    if ExamineInteractionClothingFactory.HasGeneratedAppearanceIcon(itemID, baseAppearance, gender) {
      ExamineInteractionClothingFactory.LogExternalAppearanceMappings(template, baseAppearance);
      return candidateTPP;
    }

    return n"";
  }

  public static func CanResolve(itemRecord: wref<Item_Record>, player: wref<PlayerPuppet>) -> Bool {
    let templatePath: ResRef;

    if !IsDefined(itemRecord) || !IsDefined(player) {
      return false;
    }

    templatePath = ExamineInteractionClothingFactory.ResolveTemplate(itemRecord.EntityName());
    return ResRef.IsValid(templatePath)
      && NotEquals(itemRecord.AppearanceName(), n"")
      && NotEquals(player.GetResolvedGenderName(), n"")
      && GameInstance.GetResourceDepot().ResourceExists(templatePath);
  }
}

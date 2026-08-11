module MisterChedda.ExamineInteraction

import Codeware.Localization.*

/// One exact-path exception to the automatic world prop filename formatter. Add new entries only in GetOverrides()
public class ExamineInteractionWorldPropNameOverride extends IScriptable {
  public let meshPath: String;
  public let localizationKey: String;
  public let englishName: String;

  public static func Create(meshPath: String, localizationKey: String, englishName: String) -> ref<ExamineInteractionWorldPropNameOverride> {
    let entry = new ExamineInteractionWorldPropNameOverride();
    entry.meshPath = StrLower(StrReplace(meshPath, "/", "\\"));
    entry.localizationKey = localizationKey;
    entry.englishName = englishName;
    return entry;
  }
}

public abstract class ExamineInteractionWorldPropNames {
  public static func GetOverrides() -> array<ref<ExamineInteractionWorldPropNameOverride>> {
    let entries: array<ref<ExamineInteractionWorldPropNameOverride>>;

    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\garbage\\trash\\trash_packaging\\trash_packaging_f.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-TakeoutTrash",
      "Takeout Trash"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\garbage\\trash\\trash_packaging\\trash_packaging_d.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-PizzaTrash",
      "Pizza Trash"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\garbage\\trash\\trash_packaging\\trash_packaging_h.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-CoffeeTrash",
      "Coffee Trash"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\garbage\\trash\\trash_packaging\\trash_packaging_g.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-CoffeeTrash",
      "Coffee Trash"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\garbage\\trash\\trash_packaging\\trash_packaging_a.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-TakeoutTrash",
      "Takeout Trash"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\garbage\\trash\\trash_packaging\\trash_packaging_b.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-PlateTrash",
      "Plate Trash"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\food\\drinks\\drink_packaged\\drink_packaged_a.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-DairingDiaryCowMilk",
      "Dairing Diary Cow Milk"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\food\\drinks\\drink_packaged\\drink_packaged_b.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-DairingDiaryCowMilk",
      "Dairing Diary Cow Milk"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\food\\drinks\\drink_packaged\\drink_packaged_c.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-DairingDiaryCowMilk",
      "Dairing Diary Cow Milk"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\food\\drinks\\drink_packaged\\drink_packaged_d.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-DairingDiaryCowMilk",
      "Dairing Diary Cow Milk"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\food\\drinks\\drink_packaged\\drink_packaged_e.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-DairingDiaryCowMilk",
      "Dairing Diary Cow Milk"
    ));
    ArrayPush(entries, ExamineInteractionWorldPropNameOverride.Create(
      "base\\environment\\decoration\\food\\drinks\\drink_packaged\\drink_packaged_f.mesh",
      "MisterChedda-ExamineInteraction-WorldProp-DairingDiaryCowMilk",
      "Dairing Diary Cow Milk"
    ));

    return entries;
  }

  public static func Resolve(meshPath: ResRef) -> String {
    let entries = ExamineInteractionWorldPropNames.GetOverrides();
    let i: Int32;
    let localizedName: String;
    let localizationSystem: ref<LocalizationSystem>;
    let normalizedPath = StrLower(StrReplace(ResRef.ToString(meshPath), "/", "\\"));

    while i < ArraySize(entries) {
      if Equals(normalizedPath, entries[i].meshPath) {
        localizationSystem = LocalizationSystem.GetInstance(GetGameInstance());
        if IsDefined(localizationSystem) {
          localizedName = localizationSystem.GetText(entries[i].localizationKey);
          if IsStringValid(localizedName) && NotEquals(localizedName, entries[i].localizationKey) {
            return localizedName;
          }
        }
        return entries[i].englishName;
      }
      i += 1;
    }

    return "";
  }
}

public class ExamineInteractionEnglishLocalizationPackage extends ModLocalizationPackage {
  protected func DefineTexts() -> Void {
    let entries = ExamineInteractionWorldPropNames.GetOverrides();
    let i: Int32;

    this.Text("UI_MisterChedda_Examine_PreviewLightIntensity_Name", "Preview Light Intensity");
    this.Text(
      "UI_MisterChedda_Examine_PreviewLightIntensity_Description",
      "Multiplies the inspection spotlight intensity. Set to 0 to disable its illumination."
    );
    this.Text("UI_MisterChedda_Examine_DiagnosticLogging_Name", "Diagnostic Logging");
    this.Text(
      "UI_MisterChedda_Examine_DiagnosticLogging_Description",
      "Writes detailed inspection, resolver, framing, and factory diagnostics to the game log. Enable this when reproducing an issue."
    );

    while i < ArraySize(entries) {
      this.Text(entries[i].localizationKey, entries[i].englishName);
      i += 1;
    }
  }
}

public class ExamineInteractionLocalizationProvider extends ModLocalizationProvider {
  public func GetPackage(language: CName) -> ref<ModLocalizationPackage> {
    if Equals(language, n"en-us") {
      return new ExamineInteractionEnglishLocalizationPackage();
    }
    return null;
  }

  public func GetFallback() -> CName {
    return n"en-us";
  }
}

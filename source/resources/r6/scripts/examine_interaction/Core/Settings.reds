module MisterChedda.ExamineInteraction

import MisterChedda.ExamineInteraction.Native.SetDiagnosticLogging

public class ExamineInteractionSettings extends ScriptableSystem {
  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_General")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_Enabled_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_Enabled_Description")
  public let enabled: Bool = true;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_General")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_DiagnosticLogging_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_DiagnosticLogging_Description")
  public let diagnosticLogging: Bool = false;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_Preview")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_PreviewLight_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_PreviewLight_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let previewLightEnabled: Bool = true;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_Preview")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_PreviewLightIntensity_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_PreviewLightIntensity_Description")
  @runtimeProperty("ModSettings.dependency", "previewLightEnabled")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "2.0")
  public let previewLightIntensity: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_Preview")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_PreviewDof_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_PreviewDof_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let previewDofEnabled: Bool = true;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_Preview")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_PreviewDofStrength_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_PreviewDofStrength_Description")
  @runtimeProperty("ModSettings.dependency", "previewDofEnabled")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "2.0")
  public let previewDofStrength: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_PreviewText")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_PreviewTextWeapons_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_PreviewTextWeapons_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let previewTextWeapons: Bool = true;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_PreviewText")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_PreviewTextClothing_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_PreviewTextClothing_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let previewTextClothing: Bool = true;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_PreviewText")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_PreviewTextLootables_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_PreviewTextLootables_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let previewTextLootables: Bool = true;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_PreviewText")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_PreviewTextWorldProps_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_PreviewTextWorldProps_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let previewTextWorldProps: Bool = false;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_Controls")
  @runtimeProperty("ModSettings.category.order", "4")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_KeyboardKey_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_KeyboardKey_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let examineKey: EInputKey = EInputKey.IK_G;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_Controls")
  @runtimeProperty("ModSettings.category.order", "4")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_ControllerKey_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_ControllerKey_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let examineControllerKey: EInputKey = EInputKey.IK_Pad_LeftThumb;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_Controls")
  @runtimeProperty("ModSettings.category.order", "4")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_MouseRotationSensitivity_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_MouseRotationSensitivity_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.25")
  @runtimeProperty("ModSettings.max", "3.0")
  public let mouseRotationSensitivity: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "UI_MisterChedda_Examine_ModName")
  @runtimeProperty("ModSettings.category", "UI_MisterChedda_Examine_Category_Controls")
  @runtimeProperty("ModSettings.category.order", "4")
  @runtimeProperty("ModSettings.displayName", "UI_MisterChedda_Examine_ControllerRotationSensitivity_Name")
  @runtimeProperty("ModSettings.description", "UI_MisterChedda_Examine_ControllerRotationSensitivity_Description")
  @runtimeProperty("ModSettings.dependency", "enabled")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.25")
  @runtimeProperty("ModSettings.max", "3.0")
  public let controllerRotationSensitivity: Float = 1.0;

  public static func Get(game: GameInstance) -> ref<ExamineInteractionSettings> {
    return GameInstance.GetScriptableSystemsContainer(game)
      .Get(n"MisterChedda.ExamineInteraction.ExamineInteractionSettings") as ExamineInteractionSettings;
  }

  @if(ModuleExists("ModSettingsModule"))
  private func OnAttach() -> Void {
    ModSettings.RegisterListenerToClass(this);
    ModSettings.RegisterListenerToModifications(this);
    SetDiagnosticLogging(this.diagnosticLogging);
  }

  @if(!ModuleExists("ModSettingsModule"))
  private func OnAttach() -> Void {
    SetDiagnosticLogging(this.diagnosticLogging);
  }

  @if(ModuleExists("ModSettingsModule"))
  private func OnDetach() -> Void {
    SetDiagnosticLogging(false);
    ModSettings.UnregisterListenerToClass(this);
    ModSettings.UnregisterListenerToModifications(this);
  }

  @if(!ModuleExists("ModSettingsModule"))
  private func OnDetach() -> Void {
    SetDiagnosticLogging(false);
  }

  @if(ModuleExists("ModSettingsModule"))
  private func OnModSettingsChange() -> Void {
    let service = ExamineInteractionService.Get();
    SetDiagnosticLogging(this.diagnosticLogging);
    if IsDefined(service) {
      service.OnSettingsChanged();
    }
  }
}

public abstract class ExamineInteractionLog {
  public static func DiagnosticsEnabled() -> Bool {
    let settings = ExamineInteractionSettings.Get(GetGameInstance());
    return IsDefined(settings) && settings.diagnosticLogging;
  }

  public static func Diagnostic(message: String) -> Void {
    if ExamineInteractionLog.DiagnosticsEnabled() {
      FTLog(message);
    }
  }
}

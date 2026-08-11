module MisterChedda.ExamineInteraction

@addField(LootingGameController)
private let m_examineInteractionWorldPropPrompt: ref<inkHorizontalPanel>;

@addField(LootingGameController)
private let m_examineInteractionWorldPropPromptInput: ref<inkInputDisplayController>;

@addField(LootingGameController)
private let m_examineInteractionWorldPropPromptShifted: Bool;

@addMethod(LootingGameController)
private final func ExamineInteractionHasActiveVanillaChoices() -> Bool {
  let blackboard: ref<IBlackboard>;
  let definition = GetAllBlackboardDefs().UIInteractions;
  let dialogs: DialogChoiceHubs;
  let interaction: InteractionChoiceHubData;

  blackboard = this.GetBlackboardSystem().Get(definition);
  if !IsDefined(blackboard) {
    return false;
  }

  dialogs = FromVariant<DialogChoiceHubs>(blackboard.GetVariant(definition.DialogChoiceHubs));
  if ArraySize(dialogs.choiceHubs) > 0 {
    return true;
  }

  interaction = FromVariant<InteractionChoiceHubData>(
    blackboard.GetVariant(definition.InteractionChoiceHub)
  );
  return interaction.active && ArraySize(interaction.choices) > 0;
}

@addMethod(LootingGameController)
public final func ExamineInteractionCreateWorldPropPrompt() -> Void {
  let icon: ref<inkImage>;
  let inputRoot: ref<inkCanvas>;
  let inputText: ref<inkText>;
  let inputWidget: ref<inkCanvas>;
  let label: ref<inkText>;
  let prompt: ref<inkHorizontalPanel>;
  let lootingRoot = this.GetRootWidget();
  let root: ref<inkCompoundWidget>;

  if IsDefined(lootingRoot) {
    root = lootingRoot.GetParentWidget() as inkCompoundWidget;
  }

  if IsDefined(this.m_examineInteractionWorldPropPrompt) || !IsDefined(root) {
    return;
  }

  prompt = new inkHorizontalPanel();
  prompt.SetName(n"ExamineInteractionWorldPropPrompt");
  prompt.SetAnchor(inkEAnchor.BottomCenter);
  prompt.SetAnchorPoint(Vector2(0.5, 1.0));
  prompt.SetHAlign(inkEHorizontalAlign.Center);
  prompt.SetVAlign(inkEVerticalAlign.Bottom);
  prompt.SetFitToContent(true);
  prompt.SetMargin(inkMargin(0.0, 0.0, 0.0, 180.0));
  prompt.SetVisible(false);
  prompt.Reparent(root);

  inputWidget = new inkCanvas();
  inputWidget.SetSize(64.0, 56.0);
  inputWidget.SetHAlign(inkEHorizontalAlign.Left);
  inputWidget.SetVAlign(inkEVerticalAlign.Center);
  inputWidget.SetMargin(inkMargin(0.0, 0.0, 20.0, 0.0));
  inputWidget.Reparent(prompt);

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
  icon.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
  icon.BindProperty(n"tintColor", n"MainColors.Blue");
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
  inputText.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
  inputText.BindProperty(n"tintColor", n"MainColors.Blue");
  inputText.Reparent(inputRoot);

  this.m_examineInteractionWorldPropPromptInput = new inkInputDisplayController();
  this.m_examineInteractionWorldPropPromptInput.fixedIconHeight = 42;
  this.m_examineInteractionWorldPropPromptInput.iconRef = inkWidgetRef.Create(icon);
  this.m_examineInteractionWorldPropPromptInput.nameRef = inkWidgetRef.Create(inputText);
  this.m_examineInteractionWorldPropPromptInput.canvasRef = inkWidgetRef.Create(inputRoot);
  inputWidget.AttachController(this.m_examineInteractionWorldPropPromptInput);

  label = new inkText();
  label.SetText(GetLocalizedText("Gameplay-Devices-Interactions-Inspect"));
  label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
  label.SetFontStyle(n"Medium");
  label.SetFontSize(42);
  label.SetTracking(2);
  label.SetFitToContent(true);
  label.SetVAlign(inkEVerticalAlign.Center);
  label.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
  label.BindProperty(n"tintColor", n"MainColors.Blue");
  label.Reparent(prompt);

  this.m_examineInteractionWorldPropPrompt = prompt;
}

@addMethod(LootingGameController)
public final func ExamineInteractionSetWorldPropPrompt(show: Bool, key: EInputKey) -> Void {
  let shiftForVanillaChoices: Bool;
  let inputData: inkInputKeyData;

  this.ExamineInteractionCreateWorldPropPrompt();
  if !IsDefined(this.m_examineInteractionWorldPropPrompt) {
    return;
  }

  if IsDefined(this.m_examineInteractionWorldPropPromptInput) {
    inkInputKeyData.SetInputKey(inputData, key);
    inkInputKeyData.SetIsHoldInput(inputData, false);
    this.m_examineInteractionWorldPropPromptInput.SetInputAction(n"");
    this.m_examineInteractionWorldPropPromptInput.SetInputKey(inputData);
  }

  shiftForVanillaChoices = show && this.ExamineInteractionHasActiveVanillaChoices();
  if NotEquals(shiftForVanillaChoices, this.m_examineInteractionWorldPropPromptShifted) {
    this.m_examineInteractionWorldPropPromptShifted = shiftForVanillaChoices;
    ExamineInteractionLog.Diagnostic(
      s"[ExamineInteraction] World-prop prompt collision offset changed: shifted=\(shiftForVanillaChoices)"
    );
  }
  if shiftForVanillaChoices {
    this.m_examineInteractionWorldPropPrompt.SetMargin(inkMargin(0.0, 0.0, 0.0, 0.0));
  } else {
    this.m_examineInteractionWorldPropPrompt.SetMargin(inkMargin(0.0, 0.0, 0.0, 180.0));
  }
  this.m_examineInteractionWorldPropPrompt.SetVisible(show);
}

@addMethod(LootingGameController)
public final func ExamineInteractionReleaseWorldPropPrompt() -> Void {
  let parent: ref<inkCompoundWidget>;

  if IsDefined(this.m_examineInteractionWorldPropPrompt) {
    this.m_examineInteractionWorldPropPrompt.SetVisible(false);
    parent = this.m_examineInteractionWorldPropPrompt.GetParentWidget() as inkCompoundWidget;
    if IsDefined(parent) {
      parent.RemoveChild(this.m_examineInteractionWorldPropPrompt);
    }
  }
  this.m_examineInteractionWorldPropPrompt = null;
  this.m_examineInteractionWorldPropPromptInput = null;
  this.m_examineInteractionWorldPropPromptShifted = false;
}

@wrapMethod(interactionItemLogicController)
public final func SetData(data: script_ref<InteractionChoiceData>, opt skillCheck: UIInteractionSkillCheck, opt isItemBroken: Bool) -> Void {
  wrappedMethod(data, skillCheck, isItemBroken);

  // Choice3 is only our HUD slot marker. Leaving it active on the input display lets the widget redraw the weapon-slot "1" glyph later, even after SetInputKey. Clear the action source before applying the actual configurable Codeware key
  if (Equals(Deref(data).localizedName, "Gameplay-Devices-Interactions-Inspect")
      || Equals(Deref(data).localizedName, "Examine"))
    && NotEquals(Deref(data).rawInputKey, EInputKey.IK_None) {
    let keyData: inkInputKeyData = new inkInputKeyData();
    inkInputKeyData.SetInputKey(keyData, Deref(data).rawInputKey);
    this.m_inputDisplayController.SetInputAction(n"");
    this.m_inputDisplayController.SetInputKey(keyData);
  }
}

@wrapMethod(LootingGameController)
protected cb func OnInitialize() -> Bool {
  wrappedMethod();
  this.ExamineInteractionCreateWorldPropPrompt();
  let service = ExamineInteractionService.Get();
  if IsDefined(service) {
    service.AttachController(this);
  }
}

@wrapMethod(LootingGameController)
protected cb func OnUninitialize() -> Bool {
  let service = ExamineInteractionService.Get();
  if IsDefined(service) {
    service.DetachController();
  }
  this.ExamineInteractionReleaseWorldPropPrompt();
  wrappedMethod();
}

@wrapMethod(LootingGameController)
protected cb func OnUpdateData(value: Variant) -> Bool {
  let data = FromVariant<LootData>(value);
  let service = ExamineInteractionService.Get();

  if IsDefined(service) && service.ProcessLootData(this, data) {
    wrappedMethod(ToVariant(data));
    return true;
  }

  wrappedMethod(value);
}

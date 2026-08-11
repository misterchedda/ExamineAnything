module MisterChedda.ExamineInteraction

public class ExamineInteractionPropFocusPoll extends DelayCallback {
  private let m_service: wref<ExamineInteractionService>;
  private let m_generation: Uint32;

  public static func Create(service: wref<ExamineInteractionService>, generation: Uint32) -> ref<ExamineInteractionPropFocusPoll> {
    let callback = new ExamineInteractionPropFocusPoll();
    callback.m_service = service;
    callback.m_generation = generation;
    return callback;
  }

  public func Call() -> Void {
    if IsDefined(this.m_service) {
      this.m_service.ExamineInteractionPollPropFocus(this.m_generation);
    }
  }
}

public class ExamineInteractionLootActionContext extends IScriptable {
  public let ownerID: EntityID;
  public let itemID: ItemID;
  public let choices: array<InteractionChoiceData>;
  public let actions: array<CName>;
  public let sourceChoiceIndices: array<Int32>;
}

public class ExamineInteractionLootActionDispatch extends DelayCallback {
  private let m_service: wref<ExamineInteractionService>;
  private let m_context: ref<ExamineInteractionLootActionContext>;
  private let m_choiceIndex: Int32;

  public static func Create(service: wref<ExamineInteractionService>, context: ref<ExamineInteractionLootActionContext>, choiceIndex: Int32) -> ref<ExamineInteractionLootActionDispatch> {
    let callback = new ExamineInteractionLootActionDispatch();
    callback.m_service = service;
    callback.m_context = context;
    callback.m_choiceIndex = choiceIndex;
    return callback;
  }

  public func Call() -> Void {
    if IsDefined(this.m_service) {
      this.m_service.DispatchInspectionLootAction(this.m_context, this.m_choiceIndex);
    }
  }
}

public class ExamineInteractionLootPublishDispatch extends DelayCallback {
  private let m_service: wref<ExamineInteractionService>;
  private let m_event: ref<InteractionChoiceEvent>;
  private let m_ownerID: EntityID;
  private let m_itemID: ItemID;
  private let m_choiceIndex: Int32;
  private let m_attempt: Int32;

  public static func Create(service: wref<ExamineInteractionService>, event: ref<InteractionChoiceEvent>, ownerID: EntityID, itemID: ItemID, choiceIndex: Int32, attempt: Int32) -> ref<ExamineInteractionLootPublishDispatch> {
    let callback = new ExamineInteractionLootPublishDispatch();
    callback.m_service = service;
    callback.m_event = event;
    callback.m_ownerID = ownerID;
    callback.m_itemID = itemID;
    callback.m_choiceIndex = choiceIndex;
    callback.m_attempt = attempt;
    return callback;
  }

  public func Call() -> Void {
    if IsDefined(this.m_service) {
      this.m_service.PublishInspectionLootAction(this.m_event, this.m_ownerID, this.m_itemID, this.m_choiceIndex, this.m_attempt);
    }
  }
}

public class ExamineInteractionSodaCanDrinkFinish extends DelayCallback {
  private let m_popup: ref<ExamineInteractionPopup>;
  private let m_choiceIndex: Int32;

  public static func Create(popup: ref<ExamineInteractionPopup>, choiceIndex: Int32) -> ref<ExamineInteractionSodaCanDrinkFinish> {
    let callback = new ExamineInteractionSodaCanDrinkFinish();
    callback.m_popup = popup;
    callback.m_choiceIndex = choiceIndex;
    return callback;
  }

  public func Call() -> Void {
    if IsDefined(this.m_popup) {
      this.m_popup.FinishInspectionAction(this.m_choiceIndex);
    }
  }
}

public class ExamineInteractionWeaponPreviewPoll extends DelayCallback {
  private let m_factory: ref<ExamineInteractionWeaponPreviewFactory>;

  public static func Create(factory: ref<ExamineInteractionWeaponPreviewFactory>) -> ref<ExamineInteractionWeaponPreviewPoll> {
    let callback = new ExamineInteractionWeaponPreviewPoll();
    callback.m_factory = factory;
    return callback;
  }

  public func Call() -> Void {
    if IsDefined(this.m_factory) {
      this.m_factory.Poll();
    }
  }
}

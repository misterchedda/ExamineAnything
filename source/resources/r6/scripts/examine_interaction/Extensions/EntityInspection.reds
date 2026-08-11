module MisterChedda.ExamineInteraction

public class MisterCheddaExamineSmartFrame extends ActionBool {
  public final func SetProperties() -> Void {
    this.actionName = n"MisterCheddaExamineSmartFrame";
    this.prop = DeviceActionPropertyFunctions.SetUpProperty_Bool(
      this.actionName,
      true,
      n"LocKey#228",
      n"LocKey#228"
    );
  }

  public func GetTweakDBChoiceRecord() -> String {
    return "MisterCheddaExamineSmartFrame";
  }
}

@wrapMethod(FrameControllerPS)
public func GetActions(out actions: array<ref<DeviceAction>>, context: GetActionsContext) -> Bool {
  let action: ref<MisterCheddaExamineSmartFrame>;
  let result = wrappedMethod(actions, context);
  let service = ExamineInteractionService.Get();

  if result
    && Equals(context.requestType, gamedeviceRequestType.Direct)
    && IsDefined(service)
    && service.IsEnabled() {
    action = new MisterCheddaExamineSmartFrame();
    action.clearanceLevel = 2;
    action.SetUp(this);
    action.SetProperties();
    action.SetExecutor(context.processInitiatorObject);
    action.AddDeviceName(this.m_deviceName);
    action.CreateInteraction();
    ArrayPush(actions, action);
  }

  return result;
}

@addMethod(FrameControllerPS)
public final func OnMisterCheddaExamineSmartFrame(evt: ref<MisterCheddaExamineSmartFrame>) -> EntityNotificationType {
  this.UseNotifier(evt);
  return EntityNotificationType.SendThisEventToEntity;
}

@addMethod(Frame)
protected cb func OnMisterCheddaExamineSmartFrame(evt: ref<MisterCheddaExamineSmartFrame>) -> Bool {
  let service = ExamineInteractionService.Get();
  if IsDefined(service) {
    service.ShowWorldEntity(this);
  }
  return true;
}

@addMethod(Frame)
public final func ExamineInteractionCopyPhotoTo(target: ref<Frame>) -> Bool {
  let sourcePS: ref<FramePS>;
  let switchEvent: ref<FrameSwitch>;

  if !IsDefined(target) {
    return false;
  }

  sourcePS = this.GetPS();
  if !IsDefined(sourcePS) {
    return false;
  }

  switchEvent = new FrameSwitch();
  switchEvent.hash = sourcePS.GetHash();
  switchEvent.index = sourcePS.GetIndex();
  switchEvent.uv = sourcePS.GetUV();
  target.QueueEvent(switchEvent);
  return true;
}

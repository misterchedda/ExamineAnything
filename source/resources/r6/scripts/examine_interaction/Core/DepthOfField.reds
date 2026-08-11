module MisterChedda.ExamineInteraction

import MisterChedda.ExamineInteraction.Native.*

public class ExamineInteractionSceneDOF extends ScriptableService {
  private let m_dofOnScene: ref<scnSceneResource>;
  private let m_dofOffScene: ref<scnSceneResource>;
  private let m_swapScene: ref<scnSceneResource>;
  private let m_dofOnReady: Bool;
  private let m_dofOffReady: Bool;
  private let m_factListenerId: Uint32;
  private let m_shouldModify: Bool;
  private let m_resetRequested: Bool;
  private let m_entryName: CName;
  private let m_hardTierActive: Bool;
  private let m_previousTier: GameplayTier;
  private let m_dofSettingCaptured: Bool;
  private let m_previousDofSetting: Bool;
  private let m_directProbeActive: Bool;
  private let m_nativeDofActive: Bool;
  private let m_swapGeneration: Uint32;
  private let m_hasQueuedRequest: Bool;
  private let m_queuedReset: Bool;
  private let m_queuedFocusDistance: Float;
  private let m_queuedEntryName: CName;

  private cb func OnLoad() {
    let token: ref<ResourceToken>;

    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Resource/PostLoad", this, n"ProcessScene")
      .AddTarget(ResourceTarget.Path(r"base\\quest\\primary_characters\\vsets\\vset_v.scene"));

    token = GameInstance.GetResourceDepot()
      .LoadResource(r"misterchedda\\examine_interaction\\scenes\\dyn\\dyn_dof.scene");
    token.RegisterCallback(this, n"OnDofOnSceneReady");
    FTLog("[ExamineInteraction] Voiceset DOF bridge loaded; waiting for authored scene resource.");
  }

  private cb func OnDofOnSceneReady(token: ref<ResourceToken>) {
    this.m_dofOnScene = token.GetResource() as scnSceneResource;
    this.m_dofOnReady = IsDefined(this.m_dofOnScene)
      && IsDefined(this.m_dofOnScene.sceneGraph);

    if this.m_dofOnReady {
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] Authored DOF scene loaded for voiceset swap.");
    } else {
      FTLog("[ExamineInteraction] Authored DOF scene failed to load.");
    }
  }

  private cb func OnDofOffSceneReady(token: ref<ResourceToken>) {
    this.m_dofOffScene = token.GetResource() as scnSceneResource;
    this.m_dofOffReady = this.PrepareScene(this.m_dofOffScene, true, n"examine_dof_off");

    if this.m_dofOffReady {
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] DOF-off scene loaded and prepared.");
    } else {
      FTLog("[ExamineInteraction] DOF-off scene failed to load or prepare.");
    }
  }

  public func Apply(focusDistance: Float, focusRadius: Float, intensity: Float) -> Void {
    let appliedIntensity: Float;
    let farBlur: Float;
    let farFocus: Float;
    let strengthMultiplier: Float = 1.0;
    let settings = ExamineInteractionSettings.Get(GetGameInstance());

    if IsDefined(settings) {
      strengthMultiplier = ClampF(settings.previewDofStrength, 0.0, 2.0);
    }
    appliedIntensity = intensity * strengthMultiplier;

    if (IsDefined(settings) && !settings.previewDofEnabled) || appliedIntensity <= 0.0 {
      if this.m_nativeDofActive || this.m_directProbeActive || this.m_dofSettingCaptured {
        this.Reset();
      }
      return;
    }

    this.EnableDepthOfFieldSetting();

    farFocus = ClampF(focusDistance + focusRadius * 0.35, 0.30, 1.50);
    farBlur = ClampF(farFocus + MaxF(0.65, focusRadius * 1.50), 0.95, 3.00);
    if SetDof(
      appliedIntensity,
      -1.0,
      -1.0,
      farBlur,
      farFocus,
      false,
      true
    ) {
      this.m_nativeDofActive = true;
      return;
    }

    FTLog("[ExamineInteraction] Native render-camera DOF override unavailable; using authored scene fallback.");
    this.ConfigureAuthoredFocus(focusDistance, focusRadius, appliedIntensity);
    this.Request(false, focusDistance, n"dof_on");
  }

  private final func ApplyDirectCameraDOF(focusDistance: Float, focusRadius: Float) -> Void {
    let camera: ref<FPPCameraComponent>;
    let farBlur: Float;
    let farFocus: Float;
    let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(GetGameInstance())
      .GetLocalPlayerControlledGameObject() as PlayerPuppet;

    if !IsDefined(player) {
      FTLog("[ExamineInteraction] DIRECT CAMERA DOF PROBE failed: player is unavailable.");
      return;
    }

    camera = player.GetFPPCameraComponent();
    if !IsDefined(camera) {
      FTLog("[ExamineInteraction] DIRECT FPP CAMERA DOF PROBE failed: FPPCameraComponent is unavailable.");
      return;
    }

    // Leave the near plane disabled and put the far transition immediately behind the preview. These deliberately strong values should make the world blur unmistakable while keeping the examined object sharp.
    farFocus = ClampF(focusDistance + focusRadius * 0.20, 0.25, 2.50);
    farBlur = ClampF(farFocus + MaxF(0.20, focusRadius * 0.50), 0.45, 3.50);

    // FPPCameraComponent owns the actual animation-input names. Writing those inputs on its player owner bypasses both scenes and the DOFControl feature routing that did not reach the rendered camera in the previous probe.
    AnimationControllerComponent.SetInputFloat(player, camera.animParamdofNearBlur, -1.0);
    AnimationControllerComponent.SetInputFloat(player, camera.animParamdofNearFocus, -1.0);
    AnimationControllerComponent.SetInputFloat(player, camera.animParamdofFarFocus, farFocus);
    AnimationControllerComponent.SetInputFloat(player, camera.animParamdofFarBlur, farBlur);
    AnimationControllerComponent.SetInputFloat(player, camera.animParamdofIntensity, 1.0);
    this.m_directProbeActive = true;
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] DIRECT FPP CAMERA INPUT DOF PROBE applied without scene: distance=\(focusDistance) radius=\(focusRadius) intensityParam=\(NameToString(camera.animParamdofIntensity)) farFocusParam=\(NameToString(camera.animParamdofFarFocus)) farBlurParam=\(NameToString(camera.animParamdofFarBlur)) farFocus=\(farFocus) farBlur=\(farBlur)");
  }

  private final func ResetDirectCameraDOF() -> Void {
    let camera: ref<FPPCameraComponent>;
    let player: ref<PlayerPuppet>;

    if !this.m_directProbeActive {
      return;
    }

    player = GameInstance.GetPlayerSystem(GetGameInstance())
      .GetLocalPlayerControlledGameObject() as PlayerPuppet;
    if IsDefined(player) {
      camera = player.GetFPPCameraComponent();
    }

    if IsDefined(camera) {
      AnimationControllerComponent.SetInputFloat(player, camera.animParamdofIntensity, 0.0);
      AnimationControllerComponent.SetInputFloat(player, camera.animParamdofNearBlur, -1.0);
      AnimationControllerComponent.SetInputFloat(player, camera.animParamdofNearFocus, -1.0);
      AnimationControllerComponent.SetInputFloat(player, camera.animParamdofFarBlur, -1.0);
      AnimationControllerComponent.SetInputFloat(player, camera.animParamdofFarFocus, -1.0);
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] DIRECT FPP CAMERA INPUT DOF PROBE reset without scene.");
    } else {
      FTLog("[ExamineInteraction] DIRECT FPP CAMERA INPUT DOF PROBE reset skipped: player or camera is unavailable.");
    }

    this.m_directProbeActive = false;
  }

  private final func ConfigureAuthoredFocus(focusDistance: Float, focusRadius: Float, intensity: Float) -> Bool {
    let cameraEvent: ref<scneventsCameraParamsEvent>;
    let cameraEventCount: Int32;
    let farBlur: Float;
    let farFocus: Float;
    let i: Int32;
    let section: ref<scnSectionNode>;

    if !this.m_dofOnReady
      || !IsDefined(this.m_dofOnScene)
      || !IsDefined(this.m_dofOnScene.sceneGraph)
      || ArraySize(this.m_dofOnScene.sceneGraph.graph) < 2 {
      FTLog("[ExamineInteraction] Dynamic DOF focus skipped: authored scene is unavailable.");
      return false;
    }

    section = this.m_dofOnScene.sceneGraph.graph[1] as scnSectionNode;
    if !IsDefined(section) {
      FTLog("[ExamineInteraction] Dynamic DOF focus skipped: dof_on section is unavailable.");
      return false;
    }

    i = 0;
    while i < ArraySize(section.events) {
      cameraEvent = section.events[i] as scneventsCameraParamsEvent;
      if IsDefined(cameraEvent) {
        cameraEventCount += 1;
        if cameraEventCount == 2 {
          farFocus = ClampF(focusDistance + focusRadius * 0.35, 0.30, 1.50);
          farBlur = ClampF(farFocus + MaxF(0.65, focusRadius * 1.50), 0.95, 3.00);
          cameraEvent.dofIntensity = intensity;
          cameraEvent.dofFarFocus = farFocus;
          cameraEvent.dofFarBlur = farBlur;
          cameraEvent.startTime = 500u;
          cameraEvent.duration = 250u;
          ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Dynamic authored DOF target configured: distance=\(focusDistance) boundsRadius=\(focusRadius) intensity=\(intensity) farFocus=\(farFocus) farBlur=\(farBlur) blend=\(cameraEvent.duration)");
          return true;
        }
      }
      i += 1;
    }

    FTLog(s"[ExamineInteraction] Dynamic DOF focus skipped: expected second authored camera event, found=\(cameraEventCount)");
    return false;
  }

  private cb func OnSceneExecutionFactChanged(value: Int32) -> Void {
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] SCENE EXECUTION FACT CHANGED: examine_interaction_scene_executed=\(value)");
  }

  private final func ReadPlayerTier() -> GameplayTier {
    let blackboard: ref<IBlackboard>;
    let player: ref<GameObject> = GameInstance.GetPlayerSystem(GetGameInstance())
      .GetLocalPlayerControlledGameObject();

    if !IsDefined(player) {
      return GameplayTier.Undefined;
    }

    blackboard = GameInstance.GetBlackboardSystem(GetGameInstance())
      .GetLocalInstanced(player.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
    if !IsDefined(blackboard) {
      return GameplayTier.Undefined;
    }

    return IntEnum<GameplayTier>(blackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.SceneTier));
  }

  private final func ExecuteHardTier(tier: GameplayTier, forceEmptyHands: Bool) -> Void {
    let node: ref<questSceneManagerNodeDefinition> = new questSceneManagerNodeDefinition();
    let nodeType: ref<questSetTier_NodeType> = new questSetTier_NodeType();

    nodeType.tier = tier;
    nodeType.forceEmptyHands = forceEmptyHands;
    nodeType.useEnterAnim = false;
    nodeType.useExitAnim = false;
    nodeType.usePlayerWorkspot = false;
    node.type = nodeType;

    GameInstance.GetQuestsSystem(GetGameInstance()).ExecuteNode(node);
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Executed hard quest scene tier=\(EnumInt(tier)) forceEmptyHands=\(forceEmptyHands)");
  }

  private final func ApplyHardTier() -> Void {
    if this.m_hardTierActive {
      return;
    }

    this.m_previousTier = this.ReadPlayerTier();
    if Equals(this.m_previousTier, GameplayTier.Undefined) {
      this.m_previousTier = GameplayTier.Tier1_FullGameplay;
    }

    this.m_hardTierActive = true;
    this.ExecuteHardTier(GameplayTier.Tier4_FPPCinematic, true);
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Hard Tier4 active; captured previous tier=\(EnumInt(this.m_previousTier))");
  }

  public func Reset() -> Void {
    if this.m_nativeDofActive {
      ResetDof();
      this.m_nativeDofActive = false;
      this.RestoreDepthOfFieldSetting();
      ExamineInteractionLog.Diagnostic("[ExamineInteraction] Native render-camera DOF override released and graphics setting restored.");
      return;
    }

    this.Request(true, 0.0, n"dof_off");
    this.RestoreDepthOfFieldSetting();
    ExamineInteractionLog.Diagnostic("[ExamineInteraction] Authored DOF release requested and graphics setting override restored.");
  }

  private final func EnableDepthOfFieldSetting() -> Void {
    let dofSetting: ref<ConfigVarBool>;
    let settings: ref<UserSettings> = GameInstance.GetSettingsSystem(GetGameInstance());

    if !IsDefined(settings) {
      FTLog("[ExamineInteraction] Could not enable DOF: UserSettings is unavailable.");
      return;
    }

    dofSetting = settings.GetVar(n"/graphics/basic", n"DepthOfField") as ConfigVarBool;
    if !IsDefined(dofSetting) {
      FTLog("[ExamineInteraction] Could not enable DOF: /graphics/basic/DepthOfField is unavailable.");
      return;
    }

    if !this.m_dofSettingCaptured {
      this.m_previousDofSetting = dofSetting.GetValue();
      this.m_dofSettingCaptured = true;
    }

    if !dofSetting.GetValue() {
      dofSetting.SetValue(true);
      settings.ConfirmChanges();
    }

  }

  private final func RestoreDepthOfFieldSetting() -> Void {
    let dofSetting: ref<ConfigVarBool>;
    let settings: ref<UserSettings>;

    if !this.m_dofSettingCaptured {
      return;
    }

    settings = GameInstance.GetSettingsSystem(GetGameInstance());
    if IsDefined(settings) {
      dofSetting = settings.GetVar(n"/graphics/basic", n"DepthOfField") as ConfigVarBool;
    }

    if IsDefined(dofSetting) && NotEquals(dofSetting.GetValue(), this.m_previousDofSetting) {
      dofSetting.SetValue(this.m_previousDofSetting);
      settings.ConfirmChanges();
    }

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] DOF setting restored to \(this.m_previousDofSetting)");
    this.m_dofSettingCaptured = false;
  }

  private final func Request(reset: Bool, focusDistance: Float, entryName: CName) -> Void {
    let params: questPlayVoiceset_NodeTypeParams;
    let playerRef: EntityReference;
    let voNode: ref<questVoicesetManagerNodeDefinition>;

    if this.m_shouldModify {
      this.m_hasQueuedRequest = true;
      this.m_queuedReset = reset;
      this.m_queuedFocusDistance = focusDistance;
      this.m_queuedEntryName = entryName;
      ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Scene DOF request queued behind pending swap. reset=\(reset) entry=\(NameToString(entryName)) generation=\(this.m_swapGeneration)");
      return;
    }

    if !this.m_dofOnReady || !IsDefined(this.m_dofOnScene) {
      FTLog(s"[ExamineInteraction] DOF scene request ignored because the authored scene is not ready. reset=\(reset)");
      return;
    }
    this.m_swapScene = this.m_dofOnScene;

    this.m_resetRequested = reset;
    this.m_entryName = entryName;

    voNode = new questVoicesetManagerNodeDefinition();
    voNode.type = new questPlayVoiceset_NodeType();
    params.isPlayer = true;
    params.overrideVisualStyle = true;
    params.overrideVoiceoverExpression = true;
    params.voicesetName = entryName;
    playerRef.reference = CreateNodeRef("#player");
    params.puppetRef = playerRef;
    ArrayPush((voNode.type as questPlayVoiceset_NodeType).params, params);

    this.m_shouldModify = true;
    this.m_swapGeneration += 1u;
    GameInstance.GetQuestsSystem(GetGameInstance()).ExecuteNode(voNode);
    GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(
      ExamineInteractionSceneSwapWatchdog.Create(this, this.m_swapGeneration),
      1.0,
      false
    );
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Executed voiceset scene request entry=\(NameToString(entryName)) reset=\(reset) focus=\(focusDistance) generation=\(this.m_swapGeneration)");
  }

  public func OnSceneSwapWatchdog(generation: Uint32) -> Void {
    if NotEquals(generation, this.m_swapGeneration) || !this.m_shouldModify {
      return;
    }

    FTLog(s"[ExamineInteraction] SCENE SWAP WATCHDOG cancelled orphaned pending swap: entry=\(NameToString(this.m_entryName)) reset=\(this.m_resetRequested) generation=\(generation)");
    this.m_shouldModify = false;
    this.m_swapScene = null;
    this.FlushQueuedRequest();
  }

  private final func FlushQueuedRequest() -> Void {
    let entryName: CName;
    let focusDistance: Float;
    let reset: Bool;

    if !this.m_hasQueuedRequest {
      return;
    }

    reset = this.m_queuedReset;
    focusDistance = this.m_queuedFocusDistance;
    entryName = this.m_queuedEntryName;
    this.m_hasQueuedRequest = false;
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Dispatching queued Scene DOF request: reset=\(reset) entry=\(NameToString(entryName))");
    this.Request(reset, focusDistance, entryName);
  }

  private final func PrepareScene(scene: ref<scnSceneResource>, reset: Bool, entryName: CName) -> Bool {
    let applyEvent: ref<scneventsCameraParamsEvent>;
    let eventSocket: ref<scneventsSocket>;
    let factNode: ref<scnQuestNode>;
    let overrideSettings: scneventsCameraOverrideSettings;
    let resetEvent: ref<scneventsCameraParamsEvent>;
    let section: ref<scnSectionNode>;
    let startNode: ref<scnStartNode>;
    let tierEvent: ref<scnPlaySkAnimEvent>;

    if reset {
      FTLog("[ExamineInteraction] Authored scene validator rejected a reset-only request.");
      return false;
    }

    if !IsDefined(scene)
      || !IsDefined(scene.sceneGraph)
      || ArraySize(scene.sceneGraph.graph) != 4 {
      FTLog("[ExamineInteraction] Authored DOF scene graph is unavailable or does not contain the expected four nodes.");
      return false;
    }

    startNode = scene.sceneGraph.graph[0] as scnStartNode;
    section = scene.sceneGraph.graph[1] as scnSectionNode;
    factNode = scene.sceneGraph.graph[2] as scnQuestNode;
    if !IsDefined(startNode)
      || !IsDefined(section)
      || !IsDefined(factNode)
      || ArraySize(section.events) != 4
      || ArraySize(section.outputSockets) != 4 {
      FTLog("[ExamineInteraction] Authored DOF scene node, event, or socket layout is invalid.");
      return false;
    }

    tierEvent = section.events[0] as scnPlaySkAnimEvent;
    applyEvent = section.events[1] as scneventsCameraParamsEvent;
    eventSocket = section.events[2] as scneventsSocket;
    resetEvent = section.events[3] as scneventsCameraParamsEvent;
    if !IsDefined(tierEvent) || !IsDefined(applyEvent) || !IsDefined(eventSocket) || !IsDefined(resetEvent) {
      FTLog("[ExamineInteraction] Authored DOF scene event types are invalid.");
      return false;
    }

    // RHT camera-tuning block. The archive owns the scene structure; these values are reapplied to its cached event objects on every Examine press.
    overrideSettings.overrideDof = true;
    overrideSettings.resetDof = false;
    overrideSettings.overrideFov = true;
    overrideSettings.resetFov = false;
    applyEvent.cameraOverrideSettings = overrideSettings;

    applyEvent.startTime = 500u;
    applyEvent.duration = 1000u;
    applyEvent.fovValue = 20.0;
    applyEvent.fovWeigh = 1.0;
    applyEvent.dofIntensity = 1.0;
    applyEvent.dofNearBlur = 0.002;
    applyEvent.dofNearFocus = 0.001;
    applyEvent.dofFarFocus = 0.001;
    applyEvent.dofFarBlur = 0.002;
    applyEvent.useNearPlane = false;
    applyEvent.useFarPlane = true;

    // Tier 4 gives the section cinematic camera authority. Keep the probe time-bounded so the player automatically returns to gameplay state.
    tierEvent.duration = 5000u;
    resetEvent.startTime = 4500u;
    resetEvent.duration = 500u;
    section.sectionDuration.stu = 5000u;

    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Applied Tier4 camera probe entry=\(NameToString(entryName)) entryNode=\(startNode.nodeId.id) tierDuration=\(tierEvent.duration) start=\(applyEvent.startTime) blend=\(applyEvent.duration) fov=\(applyEvent.fovValue) intensity=\(applyEvent.dofIntensity) farFocus=\(applyEvent.dofFarFocus) farBlur=\(applyEvent.dofFarBlur) resetAt=\(resetEvent.startTime)");
    return true;
  }

  private cb func ProcessScene(event: ref<ResourceEvent>) {
    let probeFact: Int32;
    let scene: ref<scnSceneResource>;

    if !this.m_shouldModify {
      return;
    }

    scene = event.GetResource() as scnSceneResource;
    if !IsDefined(scene) || !IsDefined(scene.sceneGraph) {
      FTLog("[ExamineInteraction] Voiceset scene interception produced no scene resource.");
      this.m_shouldModify = false;
      this.m_swapScene = null;
      this.FlushQueuedRequest();
      return;
    }

    if !IsDefined(this.m_swapScene) {
      FTLog("[ExamineInteraction] Scene swap aborted because its prepared resource is unavailable.");
      this.m_shouldModify = false;
      this.m_swapScene = null;
      this.FlushQueuedRequest();
      return;
    }

    scene.sceneGraph.graph = this.m_swapScene.sceneGraph.graph;
    scene.sceneGraph.startNodes = this.m_swapScene.sceneGraph.startNodes;
    scene.entryPoints = this.m_swapScene.entryPoints;
    scene.voInfo = this.m_swapScene.voInfo;
    scene.screenplayStore = this.m_swapScene.screenplayStore;
    scene.resouresReferences = this.m_swapScene.resouresReferences;
    scene.workspotInstances = this.m_swapScene.workspotInstances;
    scene.workspots = this.m_swapScene.workspots;
    // scene.sceneCategoryTag = scnSceneCategoryTag.mainQuests;

    this.m_shouldModify = false;
    this.m_swapScene = null;
    probeFact = GameInstance.GetQuestsSystem(GetGameInstance())
      .GetFact(n"examine_interaction_scene_executed");
    ExamineInteractionLog.Diagnostic(s"[ExamineInteraction] Indiana Jones scene swap complete. entry=\(NameToString(this.m_entryName)) reset=\(this.m_resetRequested) probeFact=\(probeFact)");
    this.FlushQueuedRequest();
  }
}

public class ExamineInteractionSceneSwapWatchdog extends DelayCallback {
  private let m_service: ref<ExamineInteractionSceneDOF>;
  private let m_generation: Uint32;

  public static func Create(service: ref<ExamineInteractionSceneDOF>, generation: Uint32) -> ref<ExamineInteractionSceneSwapWatchdog> {
    let callback: ref<ExamineInteractionSceneSwapWatchdog> = new ExamineInteractionSceneSwapWatchdog();
    callback.m_service = service;
    callback.m_generation = generation;
    return callback;
  }

  public func Call() -> Void {
    if IsDefined(this.m_service) {
      this.m_service.OnSceneSwapWatchdog(this.m_generation);
    }
  }
}

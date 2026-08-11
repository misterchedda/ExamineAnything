module MisterChedda.ExamineInteraction.Native

public native func SetDof(
  intensity: Float,
  nearBlur: Float,
  nearFocus: Float,
  farBlur: Float,
  farFocus: Float,
  useNearPlane: Bool,
  useFarPlane: Bool
) -> Bool;

public native func ResetDof() -> Bool;

public native func PrepareLootChoiceEvent(
  event: ref<InteractionChoiceEvent>,
  itemID: ItemID,
  action: CName,
  removeItem: Bool,
  illegal: Bool
) -> Bool;

public native func PublishLootChoiceEvent(
  event: ref<InteractionChoiceEvent>,
  choiceIndex: Int32
) -> Bool;

public native func SetWorldNodeVisible(
  node: wref<worldINodeInstance>,
  visible: Bool
) -> Bool;

public native func GetWorldNodeLocalBounds(
  node: wref<worldINodeInstance>
) -> Box;

public native func GetWorldNodeOrientation(
  node: wref<worldINodeInstance>
) -> Quaternion;

public native func GetWorldNodeAppearance(
  node: wref<worldINodeInstance>
) -> CName;

public native func IsWorldNodeGrouped(
  node: wref<worldINodeInstance>
) -> Bool;

public native func GetWorldNodeSelectionIndex(
  node: wref<worldINodeInstance>
) -> Int32;

public native func GetWorldNodeSelectionCount(
  node: wref<worldINodeInstance>
) -> Int32;

public native func FindWorldMeshNode(
  origin: Vector4,
  direction: Vector4,
  maxDistance: Float,
  excluded: array<wref<worldINodeInstance>>
) -> wref<worldINodeInstance>;

public native func FindWorldEntity(
  origin: Vector4,
  direction: Vector4,
  maxDistance: Float,
  excluded: array<wref<Entity>>
) -> wref<Entity>;

public native func FindWorldMeshPath(
  origin: Vector4,
  direction: Vector4,
  maxDistance: Float,
  excluded: array<ResRef>
) -> ResRef;

public native func AcquireWorldMeshCandidate()
  -> wref<worldINodeInstance>;

public class ExamineInteractionMeshProfile extends IScriptable {
  public let id: String;
  public let path: String;
  public let prefix: String;
  public let name: String;
  public let description: String;
  public let pitch: Float;
  public let yaw: Float;
  public let roll: Float;
  public let scaleMultiplier: Float;
}

public abstract class ExamineInteractionCompatibility {
  private static func NormalizePath(path: String) -> String {
    return StrLower(StrReplace(path, "/", "\\"));
  }

  private static func MatchesExact(path: String, entries: array<String>) -> Bool {
    let entry: String;
    let i = 0;

    while i < ArraySize(entries) {
      entry = ExamineInteractionCompatibility.NormalizePath(entries[i]);
      if StrLen(entry) > 0 && Equals(path, entry) {
        return true;
      }
      i += 1;
    }
    return false;
  }

  private static func MatchesPrefix(path: String, entries: array<String>) -> Bool {
    let entry: String;
    let i = 0;

    while i < ArraySize(entries) {
      entry = ExamineInteractionCompatibility.NormalizePath(entries[i]);
      if StrLen(entry) > 0 && StrBeginsWith(path, entry) {
        return true;
      }
      i += 1;
    }
    return false;
  }

  private static func ProfileFlat(profileID: String, field: String) -> TweakDBID {
    return TDBID.Create(profileID + "." + field);
  }

  private static func ResolveLocalizedProfileText(profileID: String, field: String) -> String {
    let localized: String;
    let localizationKey = TweakDBInterface.GetString(
      ExamineInteractionCompatibility.ProfileFlat(profileID, field + "LocKey"),
      ""
    );
    let literal = TweakDBInterface.GetString(
      ExamineInteractionCompatibility.ProfileFlat(profileID, field),
      ""
    );

    if IsStringValid(localizationKey) {
      if StrBeginsWith(localizationKey, "LocKey#") {
        localized = GetLocalizedText(localizationKey);
      } else {
        localized = GetLocalizedTextByKey(StringToName(localizationKey));
      }
      if IsStringValid(localized) && NotEquals(localized, localizationKey) {
        return localized;
      }
    }
    return literal;
  }

  private static func ReadMeshProfilePresentation(profile: ref<ExamineInteractionMeshProfile>) -> ref<ExamineInteractionMeshProfile> {
    let profileID = profile.id;
    profile.name = ExamineInteractionCompatibility.ResolveLocalizedProfileText(profileID, "name");
    profile.description = ExamineInteractionCompatibility.ResolveLocalizedProfileText(profileID, "description");
    profile.pitch = StringToFloat(TweakDBInterface.GetString(
      ExamineInteractionCompatibility.ProfileFlat(profileID, "pitch"),
      "0.0"
    ));
    profile.yaw = StringToFloat(TweakDBInterface.GetString(
      ExamineInteractionCompatibility.ProfileFlat(profileID, "yaw"),
      "0.0"
    ));
    profile.roll = StringToFloat(TweakDBInterface.GetString(
      ExamineInteractionCompatibility.ProfileFlat(profileID, "roll"),
      "0.0"
    ));
    profile.scaleMultiplier = StringToFloat(TweakDBInterface.GetString(
      ExamineInteractionCompatibility.ProfileFlat(profileID, "scaleMultiplier"),
      "1.0"
    ));
    if profile.scaleMultiplier <= 0.0 {
      profile.scaleMultiplier = 1.0;
    }
    return profile;
  }

  public static func ResolveMeshProfile(path: String) -> ref<ExamineInteractionMeshProfile> {
    let bestPrefixLength: Int32;
    let candidate: ref<ExamineInteractionMeshProfile>;
    let i: Int32;
    let profileIDs = TDB.GetStringArray(t"MisterChedda.ExamineInteraction.meshProfiles");
    let normalizedPath = ExamineInteractionCompatibility.NormalizePath(path);
    let result: ref<ExamineInteractionMeshProfile>;

    while i < ArraySize(profileIDs) {
      candidate = new ExamineInteractionMeshProfile();
      candidate.id = profileIDs[i];
      candidate.path = ExamineInteractionCompatibility.NormalizePath(
        TweakDBInterface.GetString(
          ExamineInteractionCompatibility.ProfileFlat(candidate.id, "path"),
          ""
        )
      );
      candidate.prefix = ExamineInteractionCompatibility.NormalizePath(
        TweakDBInterface.GetString(
          ExamineInteractionCompatibility.ProfileFlat(candidate.id, "prefix"),
          ""
        )
      );
      if IsStringValid(candidate.path) && Equals(normalizedPath, candidate.path) {
        return ExamineInteractionCompatibility.ReadMeshProfilePresentation(candidate);
      }
      if IsStringValid(candidate.prefix)
        && StrBeginsWith(normalizedPath, candidate.prefix)
        && StrLen(candidate.prefix) > bestPrefixLength {
        bestPrefixLength = StrLen(candidate.prefix);
        result = candidate;
      }
      i += 1;
    }
    return IsDefined(result)
      ? ExamineInteractionCompatibility.ReadMeshProfilePresentation(result)
      : null;
  }

  public static func IsRegisteredMesh(path: String) -> Bool {
    let normalizedPath = ExamineInteractionCompatibility.NormalizePath(path);
    return IsDefined(ExamineInteractionCompatibility.ResolveMeshProfile(normalizedPath))
      || ExamineInteractionCompatibility.MatchesExact(
        normalizedPath,
        TDB.GetStringArray(t"MisterChedda.ExamineInteraction.meshPaths")
      )
      || ExamineInteractionCompatibility.MatchesPrefix(
        normalizedPath,
        TDB.GetStringArray(t"MisterChedda.ExamineInteraction.meshPrefixes")
      );
  }

  public static func IsRegisteredEntity(path: String) -> Bool {
    let normalizedPath = ExamineInteractionCompatibility.NormalizePath(path);
    return ExamineInteractionCompatibility.MatchesExact(
        normalizedPath,
        TDB.GetStringArray(t"MisterChedda.ExamineInteraction.entityPaths")
      )
      || ExamineInteractionCompatibility.MatchesPrefix(
        normalizedPath,
        TDB.GetStringArray(t"MisterChedda.ExamineInteraction.entityPrefixes")
      );
  }
}

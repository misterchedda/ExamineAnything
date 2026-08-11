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

  public static func IsRegisteredMesh(path: String) -> Bool {
    let normalizedPath = ExamineInteractionCompatibility.NormalizePath(path);
    return ExamineInteractionCompatibility.MatchesExact(
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

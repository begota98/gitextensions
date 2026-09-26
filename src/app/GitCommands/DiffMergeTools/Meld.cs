namespace GitCommands.DiffMergeTools;

internal sealed class Meld : DiffMergeTool
{
    /// <inheritdoc />
    public override string ExeFileName => OperatingSystem.IsWindows() ? "meld.exe"
        : OperatingSystem.IsMacOS() ? "Meld"
        : "meld";

    /// <inheritdoc />
    public override string MergeCommand => "\"$LOCAL\" \"$BASE\" \"$REMOTE\" --output \"$MERGED\"";

    /// <inheritdoc />
    public override string Name => "meld";

    /// <inheritdoc />
    public override IEnumerable<string> SearchPaths => OperatingSystem.IsMacOS()
        ? ["/Applications/Meld.app/Contents/MacOS"]
        : [@"Meld\", @"Meld (x86)\"];
}

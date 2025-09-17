Write-Host "🔧 Initializing Zig Windows API development environment..."

$envVarValue = "C:\Program Files (x86)\Windows Kits\10"

# Set the environment variable for the current session
$env:ZIG_WINDOWS_SDK_PATH = $envVarValue

# Log the result
Write-Host "✅ Set ZIG_WINDOWS_SDK_PATH to:`n$envVarValue"

# Confirm it's set
if ($env:ZIG_WINDOWS_SDK_PATH) {
    Write-Host "🎉 Environment setup complete. You're ready to build with Zig!"
} else {
    Write-Host "❌ Failed to set $envVarName. Please check the path and try again."
}

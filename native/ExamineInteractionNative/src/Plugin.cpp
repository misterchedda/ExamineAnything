#include "Dof/DofOverride.hpp"
#include "Engine/Logging.hpp"
#include "Interaction/LootChoice.hpp"
#include "Version.hpp"
#include "World/WorldMesh.hpp"

#include <RedLib.hpp>
#include <RED4ext/RED4ext.hpp>

#include <Windows.h>

#include <filesystem>
#include <stdexcept>
#include <string>

namespace ExamineInteractionNative
{
namespace
{
std::filesystem::path GetModuleDirectory(RED4ext::v1::PluginHandle aHandle)
{
    std::wstring path(MAX_PATH, L'\0');
    const auto size = GetModuleFileNameW(aHandle, path.data(), static_cast<DWORD>(path.size()));
    if (size == 0)
    {
        throw std::runtime_error("ExamineInteractionNative: failed to resolve module path");
    }

    path.resize(size);
    return std::filesystem::path(path).parent_path();
}
}

void Load(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk)
{
    Logging::Initialize(aHandle, aSdk);
    Red::TypeInfoRegistrar::RegisterDiscovered();

    const bool dofReady = Dof::Attach();
    const bool worldReady = World::Attach();
    const bool interactionBridgeReady = Interaction::Attach();
    Logging::Info("Native subsystems initialized: dof=%u worldMesh=%u interactionBridge=%u.",
                  dofReady ? 1u : 0u, worldReady ? 1u : 0u,
                  interactionBridgeReady ? 1u : 0u);

    if (aSdk && aSdk->scripts)
    {
        aSdk->scripts->Add(aHandle, (GetModuleDirectory(aHandle) / L"scripts").c_str());
    }
}

void Unload()
{
    Interaction::Detach();
    // Stop world callbacks before tearing down render hooks and logging.
    World::Detach();
    Dof::Detach();
    Logging::Shutdown();
}
}

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle,
                                        RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    if (aReason == RED4ext::v1::EMainReason::Load)
    {
        ExamineInteractionNative::Load(aHandle, aSdk);
    }
    else if (aReason == RED4ext::v1::EMainReason::Unload)
    {
        ExamineInteractionNative::Unload();
    }
    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"ExamineInteractionNative";
    aInfo->author = L"misterchedda";
    aInfo->version = RED4EXT_V1_SEMVER(EXAMINE_INTERACTION_VERSION_MAJOR,
                                      EXAMINE_INTERACTION_VERSION_MINOR,
                                      EXAMINE_INTERACTION_VERSION_PATCH);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}

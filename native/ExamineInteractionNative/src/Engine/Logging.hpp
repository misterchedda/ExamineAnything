#pragma once

#include <RED4ext/RED4ext.hpp>
#include <atomic>

namespace ExamineInteractionNative::Logging
{
inline RED4ext::v1::PluginHandle g_pluginHandle{};
inline const RED4ext::v1::Sdk* g_sdk{};

inline std::atomic<bool> g_diagnosticsEnabled{false};

inline bool DiagnosticsEnabled()
{
    return g_diagnosticsEnabled.load(std::memory_order_relaxed);
}

inline void SetDiagnosticLogging(bool aEnabled)
{
    g_diagnosticsEnabled.store(aEnabled, std::memory_order_relaxed);
}

inline void Initialize(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk)
{
    g_pluginHandle = aHandle;
    g_sdk = aSdk;
}

inline void Shutdown()
{
    g_sdk = nullptr;
    g_pluginHandle = {};
}

template<typename... Args>
void Info(const char* aFormat, Args... aArgs)
{
    if (g_sdk && g_sdk->logger && g_sdk->logger->InfoF)
    {
        g_sdk->logger->InfoF(g_pluginHandle, aFormat, aArgs...);
    }
}

template<typename... Args>
void Diagnostic(const char* aFormat, Args... aArgs)
{
    if (DiagnosticsEnabled())
        Info(aFormat, aArgs...);
}

template<typename... Args>
void Error(const char* aFormat, Args... aArgs)
{
    if (g_sdk && g_sdk->logger && g_sdk->logger->ErrorF)
    {
        g_sdk->logger->ErrorF(g_pluginHandle, aFormat, aArgs...);
    }
}
}

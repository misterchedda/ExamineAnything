#pragma once

namespace ExamineInteractionNative::Dof
{
bool Attach();
void Detach();

bool Set(float aIntensity, float aNearBlur, float aNearFocus, float aFarBlur,
         float aFarFocus, bool aUseNearPlane, bool aUseFarPlane);
bool Reset();
}

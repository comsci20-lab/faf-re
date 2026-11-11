#include "moho/audio/RecoverableCue.h"

#include <gtest/gtest.h>

namespace
{
  class Cue final : public moho::IXACTCue
  {
  public:
    int state = XACT_CUESTATE_PLAYING;
    int destroys = 0;
    int plays = 0;
    float variable = 0;
    bool failPlay = false;
    bool failState = false;
    std::int32_t __stdcall Play() override { ++plays; return failPlay ? E_FAIL : 0; }
    void __stdcall Stop(std::int32_t) override { state = XACT_CUESTATE_STOPPED; }
    std::int32_t __stdcall GetState(std::int32_t* out) override
    {
      if (failState) return E_FAIL;
      *out = state;
      return 0;
    }
    std::int32_t __stdcall Destroy() override { ++destroys; return 0; }
    void __stdcall Reserved10() override {}
    void __stdcall Reserved14() override {}
    void __stdcall Reserved18() override {}
    void __stdcall Reserved1C() override {}
    std::int32_t __stdcall SetMatrixCoefficients(std::uint32_t, std::uint32_t, const float*) override { return 0; }
    std::uint16_t __stdcall GetVariableIndex(const char*) override { return 3; }
    std::int32_t __stdcall SetVariable(std::uint16_t, float value) override { variable = value; return 0; }
  };

  class Bank final : public moho::IXACTSoundBank
  {
  public:
    Cue cue;
    bool ready = true;
    std::uint16_t preparedIndex = 0;
    std::uint16_t __stdcall GetCueIndex(const char*) override { return 9; }
    std::int32_t __stdcall Reserved04() override { return 0; }
    std::int32_t __stdcall Reserved08() override { return 0; }
    std::int32_t __stdcall Prepare(std::uint16_t index, std::uint32_t, std::uint32_t, moho::IXACTCue** out) override
    {
      if (!ready) return E_FAIL;
      preparedIndex = index;
      *out = &cue;
      return 0;
    }
    std::int32_t __stdcall Play(std::uint16_t, std::uint32_t, std::uint32_t, moho::IXACTCue**) override { return E_FAIL; }
    std::int32_t __stdcall Reserved14() override { return 0; }
    void __stdcall Destroy() override {}
  };
}

TEST(AudioRecovery, RetainedHandleReplaysWithVariablesOnReplacementBank)
{
  std::set<moho::RecoverableCue*> registry;
  Cue old;
  auto* handle = new moho::RecoverableCue(registry, &old, 2, 9, false);
  handle->SetVariable(handle->GetVariableIndex("Distance"), 42);
  handle->Detach();
  EXPECT_EQ(old.destroys, 1);
  EXPECT_EQ(handle->GetVariableIndex("Distance"), 3);
  Bank bank;
  bank.ready = false;
  EXPECT_FALSE(handle->Restore(&bank));
  bank.ready = true;
  ASSERT_TRUE(handle->Restore(&bank));
  EXPECT_EQ(bank.preparedIndex, 9);
  EXPECT_EQ(bank.cue.plays, 1);
  EXPECT_EQ(bank.cue.variable, 42);
  EXPECT_TRUE(handle->Restore(&bank));
  EXPECT_EQ(bank.cue.plays, 1);
  handle->Destroy();
  EXPECT_TRUE(registry.empty());
  EXPECT_EQ(bank.cue.destroys, 1);
}

TEST(AudioRecovery, StopDuringDisconnectionPreventsReplay)
{
  std::set<moho::RecoverableCue*> registry;
  Cue old;
  auto* handle = new moho::RecoverableCue(registry, &old, 0, 9, false);
  handle->Detach();
  handle->Stop(0);
  Bank bank;
  EXPECT_TRUE(handle->Restore(&bank));
  EXPECT_EQ(bank.cue.plays, 0);
  int state = 0;
  EXPECT_EQ(handle->GetState(&state), 0);
  EXPECT_EQ(state, XACT_CUESTATE_STOPPED);
  handle->Destroy();
}

TEST(AudioRecovery, PreparedCueWaitsForExplicitPlayAndRetriesFailedPlay)
{
  std::set<moho::RecoverableCue*> registry;
  Cue old;
  old.state = XACT_CUESTATE_PREPARED;
  auto* handle = new moho::RecoverableCue(registry, &old, 0, 9, true);
  handle->Detach();
  Bank bank;
  ASSERT_TRUE(handle->Restore(&bank));
  EXPECT_EQ(bank.cue.plays, 0);
  EXPECT_EQ(handle->Play(), 0);
  handle->Detach();
  bank.cue.failPlay = true;
  EXPECT_FALSE(handle->Restore(&bank));
  bank.cue.failPlay = false;
  EXPECT_TRUE(handle->Restore(&bank));
  handle->Destroy();
}

TEST(AudioRecovery, ShutdownLeavesOutstandingHandleSafeToDestroy)
{
  Cue old;
  moho::RecoverableCue* handle;
  {
    std::set<moho::RecoverableCue*> registry;
    handle = new moho::RecoverableCue(registry, &old, 0, 9, false);
    handle->Detach(true);
  }
  int state = 0;
  EXPECT_EQ(handle->GetState(&state), 0);
  EXPECT_EQ(state, XACT_CUESTATE_STOPPED);
  handle->Destroy();
  EXPECT_EQ(old.destroys, 1);
}

TEST(AudioRecovery, FailedStateQueryDuringDeviceLossPreservesActiveCue)
{
  std::set<moho::RecoverableCue*> registry;
  Cue old;
  auto* handle = new moho::RecoverableCue(registry, &old, 0, 9, false);
  old.failState = true;
  int state = 0;
  EXPECT_EQ(handle->GetState(&state), 0);
  EXPECT_EQ(state, XACT_CUESTATE_PLAYING);
  handle->Detach();
  Bank bank;
  EXPECT_TRUE(handle->Restore(&bank));
  EXPECT_EQ(bank.cue.plays, 1);
  handle->Destroy();
}

TEST(AudioRecovery, CompletedCueDoesNotRestartAfterDeviceChange)
{
  std::set<moho::RecoverableCue*> registry;
  Cue old;
  old.state = XACT_CUESTATE_STOPPED;
  auto* handle = new moho::RecoverableCue(registry, &old, 0, 9, false);
  handle->Detach();
  Bank bank;
  EXPECT_TRUE(handle->Restore(&bank));
  EXPECT_EQ(bank.cue.plays, 0);
  handle->Destroy();
}

TEST(AudioRecovery, ExplicitPlayOfDetachedCueSchedulesRestoration)
{
  std::set<moho::RecoverableCue*> registry;
  Cue old;
  old.state = XACT_CUESTATE_STOPPED;
  bool pending = false;
  auto* handle = new moho::RecoverableCue(registry, &old, 0, 9, false, &pending);
  handle->Detach();
  Bank bank;
  EXPECT_TRUE(handle->Restore(&bank));
  EXPECT_FALSE(pending);
  EXPECT_EQ(handle->Play(), 0);
  EXPECT_TRUE(pending);
  EXPECT_TRUE(handle->Restore(&bank));
  EXPECT_EQ(bank.cue.plays, 1);
  handle->Destroy();
}

TEST(AudioRecovery, QueuedPlaySurvivesLossWhileCueIsStillPreparing)
{
  std::set<moho::RecoverableCue*> registry;
  Cue old;
  old.state = XACT_CUESTATE_PREPARING;
  auto* handle = new moho::RecoverableCue(registry, &old, 0, 9, false);
  handle->Detach();
  Bank bank;
  EXPECT_TRUE(handle->Restore(&bank));
  EXPECT_EQ(bank.cue.plays, 1);
  handle->Destroy();
}

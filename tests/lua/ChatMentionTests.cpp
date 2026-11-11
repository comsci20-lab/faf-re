#include "LuaTestSupport.h"

#include <filesystem>
#include <fstream>
#include <iterator>

namespace
{
  class ChatMention : public faf_lua_tests::LuaFixture
  {
  protected:
    std::string Source(const char* relative)
    {
      std::ifstream input(std::filesystem::path(FAF_CHAT_MENTION_DIR) / relative);
      EXPECT_TRUE(input.good()) << relative;
      return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
    }

    void SetUp() override
    {
      Run(Source("modules/matching.lua"));
    }

    void Receiver()
    {
      Run(R"(
        matching = {Normalize=Normalize, Match=Match}
        saved, pushed, clock = nil, {}, 0
        function GetSystemTimeSeconds() return clock end
        function GetSessionClients() return {{name='Microchip', ['local']=true}} end
        function import(path)
          if string.find(path, 'matching.lua', 1, true) then return matching end
          if string.find(path, 'prefs.lua', 1, true) then
            return {GetFromCurrentProfile=function() return saved end,
                    SetToCurrentProfile=function(key, value) saved=value end}
          end
          return {Push=function(value) table.insert(pushed, value) end, Clear=function() pushed={} end}
        end
      )");
      Run(Source("modules/mentions.lua"));
    }
  };

  TEST_F(ChatMention, PlayerNameAndNicknamesMatchWithoutCase)
  {
    EXPECT_EQ(Str("return Match('MICROCHIP, need help!', 'Microchip', '')"), "Microchip");
    EXPECT_EQ(Str("return Match('@MC cover north', 'Microchip', ' chip, MC ; David')"), "MC");
    EXPECT_EQ(Str("return Match('Hi David!', '', 'David')"), "David");
    EXPECT_FALSE(Bool("return Match('normal chat', '', ', ;  ' )"));
  }

  TEST_F(ChatMention, NamesAreLiteralAndCannotMatchInsideOtherNames)
  {
    EXPECT_FALSE(Bool("return Match('microchip and chips and mc_2', '', 'chip,mc')"));
    EXPECT_EQ(Str("return Match('hello [MC]+!', '[MC]+', '')"), "[MC]+");
    EXPECT_FALSE(Bool("return Match('axb help', 'a.b', '')"));
    EXPECT_EQ(Str("return Match('Davidson no, David yes', 'David', '')"), "David");
  }

  TEST_F(ChatMention, DurationDefaultsAndBounds)
  {
    EXPECT_EQ(Num("return Normalize(nil).seconds"), 10);
    EXPECT_EQ(Num("return Normalize({seconds='15'}).seconds"), 15);
    EXPECT_EQ(Num("return Normalize({seconds=-2}).seconds"), 1);
    EXPECT_EQ(Num("return Normalize({seconds=999}).seconds"), 120);
    EXPECT_EQ(Num("return Normalize({seconds=0/0}).seconds"), 10);
    EXPECT_FALSE(Bool("return Normalize({enabled=false}).enabled"));
  }

  TEST_F(ChatMention, IncomingMentionUsesSettingsAndDeduplicates)
  {
    Receiver();
    Run("Save({nicknames='MC',seconds=17}); Receive('Ally',{text='MC, help north!',to='allies',Id='1'},{});");
    EXPECT_EQ(Num("return table.getn(pushed)"), 1);
    EXPECT_EQ(Num("return pushed[1].seconds"), 17);
    EXPECT_EQ(Str("return pushed[1].sender .. ':' .. pushed[1].channel"), "Ally:ALLIES");
    Run("Receive('Ally',{text='MC, help north!',to='allies',Id='1'},{});");
    EXPECT_EQ(Num("return table.getn(pushed)"), 1);
    Run("Receive('Ally',{text='MC, help north!',to='allies',Id='2'},{});");
    EXPECT_EQ(Num("return table.getn(pushed)"), 2);
    EXPECT_EQ(Str("return saved.nicknames"), "MC");
  }

  TEST_F(ChatMention, OwnSystemLinksAndDisabledMessagesDoNotNotify)
  {
    Receiver();
    Run(R"(
      Receive('Microchip',{text='Microchip hello'}, {})
      Receive('Ally',{text='Microchip hello',to='notify'}, {})
      Receive('Ally',{text='Microchip hello'}, {Camera={}})
      Receive('Ally',{text='Microchip hello'}, {Type='ReceiveResources'})
      Save({enabled=false})
      Receive('Ally',{text='Microchip hello'}, {})
    )");
    EXPECT_EQ(Num("return table.getn(pushed)"), 0);
  }

  TEST_F(ChatMention, ObserverDoesNotUseWatchedArmiesName)
  {
    Receiver();
    Run("function GetSessionClients() return {{name='SomeoneElse'}} end; function GetFocusArmy() return 1 end");
    EXPECT_EQ(Str("return PlayerName()"), "");
    Run("Receive('Ally',{text='SomeoneElse help'}, {})");
    EXPECT_EQ(Num("return table.getn(pushed)"), 0);
  }

  TEST_F(ChatMention, ControllerHookRespectsMuteAndKeepsNormalChat)
  {
    Receiver();
    Run(R"(
      mentionModule = {Receive=Receive}
      local oldImport = import
      function import(path)
        if string.find(path,'mentions.lua',1,true) then return mentionModule end
        return oldImport(path)
      end
      visible, appends = true, 0
      function IsValidEntry(entry) return visible end
      function AppendEntry(entry) appends=appends+1 end
      function OnReceive(sender,message) AppendEntry({Text=message.text}) end
    )");
    Run(Source("hook/lua/ui/game/chat/ChatController.lua"));
    Run("visible=false; OnReceive('Ally',{text='Microchip help',Id='muted'})");
    EXPECT_EQ(Num("return table.getn(pushed)"), 0);
    EXPECT_EQ(Num("return appends"), 1);
    Run("visible=true; OnReceive('Ally',{text='Microchip help',Id='visible'})");
    EXPECT_EQ(Num("return table.getn(pushed)"), 1);
    Run("AppendEntry({Text='Microchip outgoing echo'})");
    EXPECT_EQ(Num("return table.getn(pushed)"), 1);
    EXPECT_EQ(Num("return appends"), 3);
  }

  TEST_F(ChatMention, EveryModFileCompilesInTheGameLuaParser)
  {
    for (const auto& entry : std::filesystem::recursive_directory_iterator(FAF_CHAT_MENTION_DIR)) {
      if (entry.path().extension() != ".lua") continue;
      std::ifstream input(entry.path());
      const std::string source{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
      std::string error;
      EXPECT_EQ(Load(source, &error), 0) << entry.path() << ": " << error;
    }
  }

  TEST_F(ChatMention, PopupTimerQueueAndCloseUseRealTime)
  {
    Run(R"(
      clock, groups, controls = 0, {}, {}
      function property(value)
        local p = {value=value or 0}
        function p:Set(value) self.value=value end
        return setmetatable(p,{__call=function(self) return self.value end})
      end
      function control()
        local c = {Width=property(1120),Height=property(630),Top=property(),Depth=property()}
        function c:SetSolidColor(value) self.color=value end
        function c:SetColor(value) end
        function c:SetText(value) self.text=value end
        function c:DisableHitTest() end
        function c:Destroy() self.destroyed=true end
        function c:SetNeedsFrameUpdate(value) self.updating=value end
        function c:GetTopmostDepth() return 10 end
        function c:GetStringAdvance(value) return string.len(value)*8 end
        table.insert(controls,c)
        return c
      end
      frame=control()
      function GetFrame() return frame end
      function GetSystemTimeSeconds() return clock end
      function IsDestroyed(c) return c.destroyed end
      function import(path)
        if string.find(path,'uiutil.lua',1,true) then
          return {CreateText=function(parent,text) local c=control();c.text=text;return c end}
        elseif string.find(path,'layouthelpers.lua',1,true) then
          return {ScaleNumber=function(n) return n end, AtHorizontalCenterIn=function() end,
                  AtLeftTopIn=function() end,AtCenterIn=function() end}
        elseif string.find(path,'group.lua',1,true) then
          return {Group=function() local c=control();table.insert(groups,c);return c end}
        elseif string.find(path,'bitmap.lua',1,true) then return {Bitmap=control}
        else return {WrapText=function(text) return {text} end} end
      end
    )");
    Run(Source("modules/popup.lua"));
    Run(R"(
      Push({sender='Ally',channel='ALLIES',text='Microchip help',seconds=10})
      Push({sender='Ally',channel='ALLIES',text='Microchip again',seconds=3})
      clock=10.27;groups[1]:OnFrame(0)
    )");
    EXPECT_FALSE(Bool("return groups[1].destroyed or false"));
    EXPECT_EQ(Num("return table.getn(groups)"), 1);
    Run("clock=10.29;groups[1]:OnFrame(0);clock=10.49;groups[1]:OnFrame(0)");
    EXPECT_TRUE(Bool("return groups[1].destroyed"));
    EXPECT_EQ(Num("return table.getn(groups)"), 2);
    Run(R"(
      for _,c in ipairs(controls) do
        if c.color=='ff1d2b3b' and not c.destroyed then close=c end
      end
      close:HandleEvent({Type='ButtonPress'})
      clock=clock+0.2;groups[2]:OnFrame(0)
    )");
    EXPECT_TRUE(Bool("return groups[2].destroyed"));
  }
}

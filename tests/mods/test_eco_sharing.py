from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT/'mods/Microchip-Eco-Sharing'


class AllocationTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((MOD/'modules/allocation.lua').read_text(encoding='utf-8-sig'))
        self.lua.execute('''
            s=Defaults(); s.enabled=true
            s.targets={High={MASS=true,ENERGY=true},Low={MASS=true,ENERGY=true}}
            own={stored={MASS=1000,ENERGY=1000},maxStorage={MASS=1000,ENERGY=1000}}
            allies={{id=2,name='Low',rating=900},{id=3,name='High',rating=1800}}
            scores={
                [2]={tick=100,data={resources={storage={storedMass=0,maxMass=1000,storedEnergy=0,maxEnergy=1000}}}},
                [3]={tick=100,data={resources={storage={storedMass=0,maxMass=1000,storedEnergy=0,maxEnergy=1000}}}}
            }
            last={}; tick=100
            function run() return Plan(s,own,allies,scores,tick,last) end
        ''')

    def test_equal_and_sequential_fractions_preserve_reserves(self):
        self.lua.execute('''
            local plan=run(); assert(table.getn(plan)==2)
            local mass,energy=1000,1000
            for _,gift in ipairs(plan) do
                assert(gift.MassAmount==199 and gift.EnergyAmount==124)
                mass=mass*(1-gift.Mass); energy=energy*(1-gift.Energy)
            end
            assert(math.abs(mass-602)<.001 and math.abs(energy-752)<.001)
        ''')

    def test_rank_higher_rating_first(self):
        self.lua.execute("s.mode='Rank'; local p=run(); assert(table.getn(p)==1 and p[1].name=='High' and p[1].MassAmount==399)")

    def test_manual_override_and_reset(self):
        self.lua.execute("s.mode='Rank'; s.order={'Low','High'}; assert(run()[1].name=='Low'); s.order={}; assert(run()[1].name=='High')")

    def test_equal_redistributes_limited_capacity(self):
        self.lua.execute('''
            scores[2].data.resources.storage.maxMass=50
            local p=run(); assert(p[1].name=='High' and p[1].MassAmount==349 and p[2].MassAmount==50)
        ''')

    def test_separate_recipient_ticks(self):
        self.lua.execute('''
            s.targets.High.MASS=false; s.targets.Low.ENERGY=false
            local p=run(); assert(p[1].Mass==0 and p[1].EnergyAmount==249)
            assert(p[2].Energy==0 and p[2].MassAmount==399)
        ''')

    def test_only_empty_fresh_selected_storage(self):
        self.lua.execute('''
            scores[2].data.resources.storage.storedMass=20
            scores[2].data.resources.storage.storedEnergy=20
            scores[3].tick=60; assert(table.getn(run())==0)
            scores[3].tick=100; scores[3].data.resources=nil; assert(table.getn(run())==0)
        ''')

    def test_disabled_and_full_reserves(self):
        self.lua.execute('''
            s.enabled=false; assert(table.getn(run())==0)
            s.enabled=true; s.massReserve=100; s.energyReserve=100; assert(table.getn(run())==0)
        ''')

    def test_cooldown_and_unrated_last(self):
        self.lua.execute('''
            s.mode='Rank'; last[3]={MASS=90,ENERGY=90}; assert(run()[1].name=='Low')
            last={}; allies[2].rating=nil; assert(run()[1].name=='Low')
        ''')


class RuntimeTests(unittest.TestCase):
    def test_sync_registration_authority_and_dispatch(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute((MOD/'modules/allocation.lua').read_text(encoding='utf-8-sig'))
        lua.execute('''
            allocate={Defaults=Defaults,Plan=Plan}
            allocate.Ordered=Ordered
            saved=Defaults(); saved.enabled=true; saved.mode='Rank'; saved.targets={Ally={MASS=true,ENERGY=true},Enemy={MASS=true,ENERGY=true}}
            sent={}; replay=false; observer=false; tick=100
            function import(path) if string.find(path,'allocation') then return allocate end
                return {GetFromCurrentProfile=function() return saved end,SetToCurrentProfile=function(key,v) saved=v end} end
            function AddOnSyncHashedCallback(cb,cat,id) receive=cb; assert(cat=='Score') end
            function RemoveOnSyncHashedCallback() receive=nil end
            function GameTick() return tick end
            function GetFocusArmy() return 1 end
            function IsObserver() return observer end
            function SessionIsReplay() return replay end
            function IsAlly(a,b) return b==2 end
            function SessionGetScenarioInfo() return {Options={Ratings={Ally=2000}}} end
            function GetArmiesTable() return {armiesTable={[1]={nickname='Me'},[2]={nickname='Ally'},[3]={nickname='Enemy'}}} end
            function GetEconomyTotals() return {stored={MASS=1000,ENERGY=1000},maxStorage={MASS=1000,ENERGY=1000}} end
            function SimCallback(data) table.insert(sent,data) end
        ''')
        lua.execute((MOD/'modules/sharing.lua').read_text(encoding='utf-8-sig'))
        lua.execute('''
            Initialize()
            local data={[2]={resources={storage={storedMass=0,maxMass=1000,storedEnergy=0,maxEnergy=1000}}},
                        [3]={resources={storage={storedMass=0,maxMass=1000,storedEnergy=0,maxEnergy=1000}}}}
            observer=true; receive(data); assert(table.getn(sent)==0)
            observer=false; replay=true; receive(data); assert(table.getn(sent)==0)
            replay=false; receive(data); assert(table.getn(sent)==1)
            assert(sent[1].Func=='GiveResourcesToPlayer' and sent[1].Args.From==1 and sent[1].Args.To==2)
            receive(data); assert(table.getn(sent)==1)
            Stop(); assert(receive==nil)
        ''')


if __name__=='__main__': unittest.main()

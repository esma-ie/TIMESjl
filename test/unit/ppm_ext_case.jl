# Crafted states for ppm_ext.vda L11-58 with pp_actef.vda LVL (v4.9.7): the
# ACT_EFF preparation. The TIMES_Demo demo12 prelv checkpoint
# (test/fixtures/demo12_off_prelv) is given data no core reference run has,
# and GAMS runs ppmain.mod L616-1357 and ppm_ext.vda L11-58 itself on it
# (scripts/make_ppm_ext_unit.jl; test/unit/test_m13_ppm_ext.jl).
#
# demo12, REG1: ELCTECOA00 runs at SEASON (PRC_TSL), takes ELCCOA (its
# shadow group NRG) and makes ELC (its primary group) and ELCCO2; it has
# ACT_EFF on ACT at ANNUAL. FTE-AGRELC (DAYNITE) takes ELC (shadow group
# NRG) and makes AGRELC. ELCREHYD00 (DAYNITE) takes ELCHYD (shadow group
# NRG) and makes ELC. RSHEOIL (ANNUAL, vintages from 2004) takes RSDOIL
# (shadow group NRG). Timeslices: ANNUAL; S, W (SEASON); SD, SN, WD, WN
# (DAYNITE).

using TIMES: TimesModel, gvalues, gmembers, gput!
import TOML

"""
The cases run by GAMS:

- "ace": ACT_EFF below the process level (ELCTECOA00 at SD and SN in 2020,
  so ACT_EFF goes to the group NRG at L50, is levelled up to S and W at
  pp_actef.vda L37-42 and dropped at ANNUAL at L45); a VDA_FLOP record of
  RSHEOIL left at the prelv checkpoint (projected into RPC_ACE at L28, so
  RSHEOIL gets an UNCD7 row without ACT_EFF below ANNUAL); ACT_EFF on
  the primary-group commodity AGRELC of FTE-AGRELC (RPG_PACE, L41-43); and
  commodity ACT_EFF on the shadow-group commodity ELCHYD of ELCREHYD00, one
  of them EPS, which the levelling copies (L46). pp_actef.vda L22 (SQRT on a
  shadow-group commodity) needs an RPG_ACE record whose group is such a
  commodity, which L38 and L54 never write (TRACKPC holds RPC_ACE's
  commodities, L35, and L54 writes commodity types): no state reaches it.
- "upl": ramping and partial loads: ACT_UPS on ELCTECOA00 and on a trade
  process (RP_UPL, L13-14), ACT_LOSPL 'FX' on ELCTECOA00 (RP_PL, L15), which
  keeps its NRG group out of the singleton groups (pp_actef.vda L19), with
  ACT_EFF at S and W; ACT_EFF at S and W on RSHEOIL (ANNUAL), with NORTS on
  W for its past vintage 2004 (pp_actef.vda L31). NORTS on a milestone would
  also zero COM_FR there (ppmain.mod L720), and demo12's COM_FR then stops
  GAMS with a division by EPS (L729, G48).
"""
const PPM_EXT_CASES = ["ace", "upl"]

function ppm_ext_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    sw = Dict{String,String}(k => string(v) for (k, v) in fx["switches"])
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=sw)
    ae = gvalues(tm, "ACT_EFF", 5)
    ace = gmembers(tm, "RPC_ACE", 3)
    if name == "ace"
        ae[("REG1", "2020", "ELCTECOA00", "ACT", "SD")] = 0.40
        ae[("REG1", "2020", "ELCTECOA00", "ACT", "SN")] = 0.30
        gput!(tm, "VDA_FLOP", Dict(("REG1", "2010", "RSHEOIL", "NRG", "ANNUAL") => 1.1))
        ae[("REG1", "2010", "FTE-AGRELC", "AGRELC", "ANNUAL")] = 0.9
        push!(ace, ("REG1", "FTE-AGRELC", "AGRELC"))
        ae[("REG2", "2030", "ELCREHYD00", "ELCHYD", "ANNUAL")] = 0.81
        ae[("REG2", "2010", "ELCREHYD00", "ELCHYD", "ANNUAL")] = 0.0      # EPS
        push!(ace, ("REG2", "ELCREHYD00", "ELCHYD"))
    elseif name == "upl"
        gput!(tm, "ACT_UPS", Dict(("REG1", "2010", "ELCTECOA00", "ANNUAL", "FX") => 0.3,
                                  ("REG1", "2010", "IMPNRGZ", "ANNUAL", "UP") => 0.5))
        gput!(tm, "ACT_LOSPL", Dict(("REG1", "2010", "ELCTECOA00", "FX") => 0.1))
        ae[("REG1", "2010", "ELCTECOA00", "ACT", "S")] = 0.41
        ae[("REG1", "2010", "ELCTECOA00", "ACT", "W")] = 0.37
        ae[("REG1", "2004", "RSHEOIL", "ACT", "S")] = 0.8
        ae[("REG1", "2004", "RSHEOIL", "ACT", "W")] = 0.7
        ae[("REG1", "2010", "RSHEOIL", "ACT", "S")] = 0.85
        gput!(tm, "NORTS", Dict(("REG1", "2004", "W") => -Inf))   # a past vintage: ppmain.mod L720 (COM_FR) reads milestones only
    else
        error("unknown ppm_ext case $name")
    end
    gput!(tm, "ACT_EFF", ae)
    gput!(tm, "RPC_ACE", ace)
    return tm
end

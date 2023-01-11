@testset "species and formulae" begin
    @testset "species parsing" begin
        # Kurucz-style numerical codes
        @test Korg.species"01.00"   == Korg.species"H"
        @test Korg.species"101.0"   == Korg.species"H2 I"
        @test Korg.species"01.0000" == Korg.species"H I"
        @test Korg.species"02.01"   == Korg.species"He II"
        @test Korg.species"02.1000" == Korg.species"He II"
        @test Korg.species"0608"    == Korg.species"CO"
        @test Korg.species"0606"    == Korg.species"C2 I"
        @test Korg.species"606"     == Korg.species"C2 I"
        @test Korg.species"0608.00" == Korg.species"CO I"
        @test Korg.species"812.0"   == Korg.species"MgO"
        @test Korg.species"822.0"   == Korg.species"TiO"

        # The normal constructor (NOT string literal) must be used to test for failure
        # only up to two atoms are supported with numerical codes
        @test_throws ArgumentError Korg.Species("060606")
        # species which contain more than 2 tokens are invalid
        @test_throws ArgumentError Korg.Species("06.05.04")
        # Korg only goes up to uranium (Z=92)
        @test_throws Exception Korg.Species("93.01")

        #traditional-ish notation
        @test Korg.species"OOO"     == Korg.species"O3"
        @test Korg.species"H 1" == Korg.species"H I"
        @test Korg.species"H     1" == Korg.species"H I"
        @test Korg.species"H_1" == Korg.species"H I"
        @test Korg.species"H.I" == Korg.species"H I"
        @test Korg.species"H I" == Korg.species"H I"
        @test Korg.species"H 2" == Korg.species"H II"
        @test Korg.species"H2" == Korg.species"HH I"
        @test Korg.species"H" == Korg.species"H I"
        @test Korg.species"C2H4" == Korg.Species(Korg.Formula([0x01, 0x01, 0x01, 0x01, 0x06, 0x06]), 0)
        @test Korg.species"H+" == Korg.species"H II"
        @test Korg.species"OH+" == Korg.species"OH II"
        @test Korg.species"OH-" == Korg.Species(Korg.Formula("OH"), -1)

        # prevent constructing species with charges < -1.
        @test_throws ArgumentError Korg.Species("H -1")
        @test_throws ArgumentError Korg.Species("C2 -2")
    end

    @testset "distinguish atoms from molecules" begin
        @test Korg.ismolecule(Korg.Formula("H2"))
        @test Korg.ismolecule(Korg.Formula("CO"))
        @test !Korg.ismolecule(Korg.Formula("H"))
        @test !Korg.ismolecule(Korg.Formula("Li"))
    end

    @testset "break molecules into atoms" begin
        @test Korg.get_atoms(Korg.Formula("CO")) == [0x06, 0x08]
        @test Korg.get_atoms(Korg.Formula("C2")) == [0x06, 0x06]
        @test Korg.get_atoms(Korg.Formula("MgO")) == [0x08, 0x0c]
    end
end
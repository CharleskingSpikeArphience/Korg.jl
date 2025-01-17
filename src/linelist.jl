using CSV

#This type represents an individual line.
struct Line{F} 
    wl::F                     #cm
    log_gf::F                 #unitless
    species::Species           
    E_lower::F                #eV (also called the excitation potential)
    gamma_rad::F              #s^-1
    gamma_stark::F            #s^-1
    vdW::Union{F, Tuple{F,F}} #either γ_vdW [s^-1] per electron or (σ, α) from ABO theory

    @doc """
        Line(wl::F, log_gf::F, species::Species, E_lower::F, 
             gamma_rad::Union{F, Missing}=missing, gamma_stark::Union{F, Missing}=missing, 
             vdw::Union{F, Tuple{F, F}, Missing}, missing) where F <: Real

    Arguments:
     - `wl`: wavelength, in cm
     - `log_gf`: (log base 10) oscillator strength (unitless)
     - `species`: the `Species` associated with the line
     - `E_lower`: The energy (excitiation potential) of the lower energy level (eV)

    Optional Arguments (these override default recipes):
     - `gamma_rad`: Fundemental width
     - `gamma_stark`: Stark broadening width at 10,000 K (s⁻¹)
     - `vdW`: If this is present, it may may be log(Γ_vdW) (assumed if negative) or the 
        [ABO parameters](https://www.astro.uu.se/~barklem/howto.html) as packed float or a 
        `Tuple`, `(σ, α)`.

    Note the the "gamma" values here are FWHM, not HWHM, of the Lorenztian component of the line 
    profile, and are in units of s⁻¹.
    """
    function Line(wl::F, log_gf::F, species::Species, E_lower::F, 
                  gamma_rad::Union{F, Missing}=missing, gamma_stark::Union{F, Missing}=missing, 
                  vdW::Union{F, Tuple{F, F}, Missing}=missing) where F <: Real
        if ismissing(gamma_stark) || ismissing(vdW)
            gamma_stark_approx, vdW_approx = approximate_gammas(wl, species, E_lower)
            if ismissing(gamma_stark)
                gamma_stark = gamma_stark_approx
            end
            if ismissing(vdW)
                vdW = vdW_approx
            end
        end
        if ismissing(gamma_rad)
            gamma_rad = approximate_radiative_gamma(wl, log_gf)
        end
        
        if vdW isa F
            if vdW < 0 #if vdW is negative, assume it's log(Γ_vdW) 
                vdW = 10^vdW
            elseif vdW > 1 #if it's > 1 assume it's packed ABO params
                vdW = (floor(vdW) * bohr_radius_cgs * bohr_radius_cgs, vdW - floor(vdW))
            end
        end 

        new{F}(wl, log_gf, species, E_lower, gamma_rad, gamma_stark, vdW)
    end
end

# it's important that this produces something parsable by the constructor
function Base.show(io::IO, ::MIME"text/plain", line::Line)
    show(io, line.species)
    print(io, " ", round(line.wl*1e8, digits=6), " Å (log gf = ", round(line.log_gf, digits=2) ,")")
end

"""
    approximate_radiative_gamma(wl, log_gf)

Approximate radiate broadening parameter.  When using this, make sure that `log_gf` is the true 
value (not adjusted for isotopic abundance).
"""
function approximate_radiative_gamma(wl, log_gf) 
    e = electron_charge_cgs
    m = electron_mass_cgs
    c = c_cgs
    8π^2 * e^2 / (m * c * wl^2) * 10^log_gf
end

"""
    approximate_gammas(wl, species, E_lower; ionization_energies=Korg.ionization_energies)

A simplified form of the Unsoeld (1955) approximation for van der Waals broadening and the 
[Cowley 1971](https://ui.adsabs.harvard.edu/abs/1971Obs....91..139C/abstract) approximation for 
Stark broadening, evaluated at 10,000 K. 
Used for atomic lines with no vdW and stark broadening info in the linelist.

Returns `(γ_stark`, `log10(γ_vdW))` in Hz, where these are the per-perturber quantities.
For autoionizing lines (those for which E_upper > χ), Returns 0.0 for γ_vdW. Note the the "gamma" 
values here are FWHM, not HWHM, of the Lorenztian component of the line profile. 

In the calculation of `n*²`, uses the approximation that
``\\overbar{r^2} = 5/2 {n^*}^4 / Z^2``
which neglects the dependence on the angular momentum quantum number, l, in the the form given by
[Warner 1967](https://ui.adsabs.harvard.edu/abs/1967MNRAS.136..381W/abstract) (the earliest english 
work reporting the Unsoeld result).
"""
function approximate_gammas(wl, species, E_lower; ionization_energies=ionization_energies)
    Z = species.charge + 1 #Z is ionization stage, not atomic number
    if ismolecule(species) || Z > 3
        return 0.0,0.0
    end
    χ = ionization_energies[get_atoms(species.formula)[1]][Z]
    c = c_cgs
    h = hplanck_eV
    k = kboltz_cgs
    E_upper = E_lower + (h * c / wl)

    #It's not obvious to me which Rydberg constant to use here, and below in Δrbar2.  The sources
    #are not entirely clear. It doesn't make a big difference.
    nstar4_upper = (Z^2 * RydbergH_eV / (χ - E_upper))^2
    #I'm not actually able to reproduce Crowley 1971 equation 7 (his simplified form) from equation 
    #5, but these match the values in the Turbospectrum source, so they are probably correct.
    #The constants here were calculated assuming that "v" is the mean (not modal) electron speed
    if Z == 1
        γstark = 2.25910152e-7 * nstar4_upper #Cowley (1971) equation 5 evaluated at T=10,000 K
    else
        #Cowley (1971) equation 6 @ T=10,000 K (n.b. the constant is 12/5 * that above)
        γstark = 5.42184365e-7 * nstar4_upper / (Z + 1)^2 
    end

    Δrbar2 = (5/2) * Rydberg_eV^2 * Z^2 * (1/(χ - E_upper)^2 - 1/(χ - E_lower)^2)
    if χ < E_upper
        γvdW = 0.0
    else
        # (log) γ_vdW From R J Rutten's course notes. 
        # Equations 11.29 and 11.30 from Gray 2005 are equivalent 
        γvdW = 6.33 + 0.4log10(Δrbar2) + 0.3log10(10_000) + log10(k)
    end

    γstark, γvdW
end

"""
    read_linelist(filename; format="vald", isotopic_abundances=Korg.isotopic_abundances)

Parse a linelist file, returning a vector of [`Line`](@ref)s.

The `format` keyword argument can be used to specify one of these linelist formats 
(default: `"vald"`):
- `"vald"` for a [VALD](http://vald.astro.uu.se/~vald/php/vald.php) linelist.
   These can be either "short" or "long" format, 
   "extract all" or "extract stellar".  Air wavelengths will automatically be converted into vacuum
   wavelengths, and energy levels will be automatically converted from cm``^{-1}`` to eV.
- `"kurucz"` for a [Kurucz linelist](http://kurucz.harvard.edu/linelists.html) 
   (format=kurucz_vac if it uses vacuum wavelengths; Be warned that Korg will not assume that 
   wavelengths are vacuum below 2000 Å),
- `"moog"` for a [MOOG linelist](http://www.as.utexas.edu/~chris/moog.html)
   (doesn't support broadening parameters or dissociation energies).  
- `"turbospectrum"` for a 
   [Turbospectrum linelist](https://github.com/bertrandplez/Turbospectrum2019/blob/master/DOC/Readme-Linelist_format_v.19) 
   in air wavelengths. Note that Korg doesn't make use of the (optional) orbital angular momentum quantum number, l, 
   for the upper or lower levels, so it won't fall back on generic ABO recipes when the ABO 
   parameters are not available.
   Korg's interpretation of the `fdamp` parameter is also slightly different from Turbospectrum's.
   See the documentation of the `vdW` parameter of [`Line`](@ref) for details.  Korg will error if 
   encounters an Unsoeld fudge factor, which it does not support.
- "turbospectrum_vac" for a Turbospectrum linelist in vacuum wavelengths.

For VALD and Turbospectrum linelists with isotope information available, Korg will scale log gf 
values by isotopic abundance (unless VALD has already pre-scaled them), using isotopic abundances
from [NIST](https://www.nist.gov/pml/atomic-weights-and-isotopic-compositions-relative-atomic-masses) 
([Korg.isotopic_abundances]).
To use custom isotopic abundances, just pass `isotopic_abundances` with the same structure: 
a dict mapping atomic number to a dict mapping from atomic weight to abundance.

Be warned that for linelists which are pre-scaled for isotopic abundance, the estimation of 
radiative broadening from log(gf) is not accurate.
"""
function read_linelist(fname::String; format="vald", isotopic_abundances=isotopic_abundances)
    format = lowercase(format)
    linelist = open(fname) do f
        if format == "kurucz"
            parse_kurucz_linelist(f; vacuum=false)
        elseif format == "kurucz_vac"
            parse_kurucz_linelist(f; vacuum=true)
        elseif format == "vald"
            parse_vald_linelist(f, isotopic_abundances)
        elseif format == "moog"
            parse_moog_linelist(f)
        elseif format == "turbospectrum"
            parse_turbospectrum_linelist(f, isotopic_abundances, false)
        elseif format == "turbospectrum_vac"
            parse_turbospectrum_linelist(f, isotopic_abundances, true)
        else
            throw(ArgumentError("$(format) is not a supported linelist format"))
        end
    end

    filter!(linelist) do line #filter triply+ ionized and hydrogen lines
        (0 <= line.species.charge <= 2) && (line.species != species"H_I")
    end

    #ensure linelist is sorted
    if !issorted(linelist, by=l->l.wl)
        sort!(linelist, by=l->l.wl)
    end

    linelist
end

#used to handle missing gammas in vald and kurucz lineslist parsers
tentotheOrMissing(x) = x == 0.0 ? missing : 10.0^x
idOrMissing(x) = x == 0.0 ? missing : x

function parse_kurucz_linelist(f; vacuum=false)
    lines = Line[]
    for row in eachline(f)
        row == "" && continue #skip empty lines

        #some linelists have a missing column in the wavelenth region
        if length(row) == 159 
            row = " " * row
        end
        
        #kurucz provides wavenumbers for "level 1" and "level 2", which is which is 
        #determined by parity
        E_levels = map((row[25:36], row[53:64])) do s
            #abs because Kurucz multiplies predicted values by -1
            abs(parse(Float64,s)) * c_cgs * hplanck_eV
        end

        wl_transform = vacuum ? identity : air_to_vacuum

        push!(lines, Line(wl_transform(parse(Float64, row[1:11])*1e-7), #convert from nm to cm
                     parse(Float64, row[12:18]),
                     Species(row[19:24]),
                     min(E_levels...),
                     tentotheOrMissing(parse(Float64, row[81:86])),
                     tentotheOrMissing(parse(Float64, row[87:92])),
                     idOrMissing(parse(Float64, row[93:98]))))
    end
    lines
end

function parse_vald_linelist(f, isotopic_abundances)
    lines = filter!(collect(eachline(f))) do line
        length(line) > 0 && line[1] != '#' #remove comments and empty lines
    end

    lines = replace.(lines, "'"=>"\"") #replace single quotes with double

    # is this an "extract all" or an "extract stellar" linelist?
    extractall = !occursin(r"^\s+\d", lines[1])
    firstline = extractall ? 3 : 4
    header = lines[firstline - 1]

    scale_isotopes = any(startswith.(lines, "* oscillator strengths were NOT scaled "))
    if !scale_isotopes && !any(startswith.(lines,"* oscillator strengths were scaled "))
        throw(ArgumentError("Can't parse linelist.  Can't detect whether log(gf)s are scaled by "*
                            "isotopic abundance."))
    end

    #we take the linelist to be long-format when the second line after the header starts with a 
    #space or a quote followed a space.  In some linelists the quotes are there, but in others 
    #they are not.
    shortformat = !(occursin(r"^\"? ", lines[firstline + 1])) 
    body = lines[firstline : (shortformat ? 1 : 4) : end]
    body = body[1 : findfirst(l->l[1]!='\"' || !isuppercase(l[2]), body)-1]

    CSVheader = if shortformat && extractall
        ["species", "wl", "E_low", "loggf", "gamma_rad", "gamma_stark", "gamma_vdW", "lande", 
         "reference"]
    elseif shortformat #extract stellar
        ["species", "wl", "E_low", "Vmic", "loggf", "gamma_rad", "gamma_stark", "gamma_vdW", 
         "lande", "depth", "reference"]
    else #long format (extract all or extract stellar)
        ["species", "wl", "loggf", "E_low", "J_lo", "E_up", "J_up", "lower_lande", "upper_lande",
         "mean_lande", "gamma_rad", "gamma_stark", "gamma_vdW"]
    end
    body = CSV.File(reduce(vcat, codeunits.(body.*"\n")), header=CSVheader, delim=',', 
                    silencewarnings=true)

    E_low = if contains(header, "cm") #convert E_low to eV if necessary
        body.E_low * c_cgs * hplanck_eV
    elseif contains(header, "eV")
        body.E_low
    else
        error("Can't parse linelist.  Can't determine energy units: " * E_col)
    end

    wl = 1e-8 * if contains(header, "air") #convert wls to vacuum if necessary
        air_to_vacuum.(body.wl)
    elseif contains(header, "vac")
        body.wl
    else
        error("Can't parse linelist.  Can't determine vac/air wls: " * header)
    end

    Δlog_gf = if scale_isotopes
        refs = if !shortformat #the references are on different lines
            lines[firstline+3 .+ ((0:length(body)-1) .* 4)]
        else #references are in the last column
            body.reference
        end

        map(refs) do ref
            #find things that look like (16)O or (64)Ni in reference string
            regexp = r"\((?<isotope>\d\d?\d?)\)(?<elem>\p{Lu}\p{Ll}?)"
            #add up the adjustments to log(gf) from isotopic abundances (zero if no info is present)
            log_probs = map(findall(regexp, ref)) do r
                m = match(regexp, ref[r])
                log10(isotopic_abundances[atomic_numbers[m["elem"]]][parse(Int64, m["isotope"])])
            end
            sum([0 ; log_probs])
        end
    else
        0
    end

    gamma_rad = map(wl, body.loggf, body.gamma_rad) do lambda, loggf, gamma
        if gamma == 0
            approximate_radiative_gamma(lambda, loggf)
        else
            10^gamma
        end
    end

    Line.(wl, body.loggf .+ Δlog_gf, Species.(body.species), E_low, gamma_rad,
        tentotheOrMissing.(body.gamma_stark),
        idOrMissing.(body.gamma_vdW))
end

#todo support moog linelists with broadening parameters?
function parse_moog_linelist(f)
    lines = collect(eachline(f))
    #moog format requires blank first line
    linelist = map(lines[2:end]) do line
        toks = split(line)
        Line(parse(Float64, toks[1]) * 1e-8, #convert Å to cm
             parse(Float64, toks[4]),
             Species(toks[2]),
             parse(Float64, toks[3]))
    end
    linelist
end

function parse_turbospectrum_linelist(fn, isotopic_abundances, vacuum)
    # https://github.com/bertrandplez/Turbospectrum2019/blob/master/DOC/Readme-Linelist_format_v.19

    lines = readlines(fn)
    species_headers = filter(1:length(lines)) do i
        i != length(lines) && lines[i][1] == '\'' && lines[i+1][1] == '\''
    end

    transitions_for_each_species = map(1:length(species_headers)) do header_line_ind
        first_line_ind = species_headers[header_line_ind]
        last_line_ind = if header_line_ind == length(species_headers)
            length(lines)
        else
            species_headers[header_line_ind+1] - 1
        end

        # species line might look like this (carrot is beginning of line):
        # ^'  26.000            '    1       2342
        # here, the 26 refers to Fe (works as everything else does for molecules).  The decimal part
        # is the isotop information, NOT THE CHARGE.  The "1" is the ionization starge, i.e. the 
        # charge + 1. 2341 is the number of lines.

        species_line = lines[first_line_ind]
        m = match(r"'\s*(?<formula>\d+)\.(?<isostring>\d+)\s+'\s+(?<ion>\d+)\s+(?<n_lines>\d+)\s*", 
                  species_line)
        formula = Formula(m["formula"]) 
        charge = parse(Int, m["ion"]) - 1
        spec = Korg.Species(formula, charge)
        n_lines = parse(Int, m["n_lines"])
        if last_line_ind - first_line_ind - 1 != n_lines
            error("Can't parse this line list.  The file says there are $n_lines lines for $spec, but I see $(last_line_ind - first_line_ind - 2) lines.")
        end

        isostring = m["isostring"]
        isotopic_Δ_loggf =  if !isnothing(match(r"^0+$", isostring))
            0.0
        else
            map(get_atoms(spec), 1:3:length(isostring)-2) do el, i
                m = parse(Int, isostring[i:i+2])
                log10(isotopic_abundances[el][m])
            end |> sum
        end
        map(lines[first_line_ind+2:last_line_ind]) do line
            parse_turbospectrum_linelist_transition(spec, isotopic_Δ_loggf, line, vacuum)
        end
    end
    sort!(vcat(transitions_for_each_species...), by=l->l.wl)
end

function parse_turbospectrum_linelist_transition(species, Δloggf, line, vacuum)
    # from the Turbospectrum docs (In practice linelists may have as few at 6 columns:
    #
    # For each line that follows:
    # col 1: lambda(A)  
    # col 2: Elow(eV) 
    # col 3: loggf 
    # col 4: fdamp (see below)
    # col 5: gup
    # col 6: gamma_rad (if =0, gf-value is used to compute gamma_rad)
    # col 7: gamma_Stark (may be omitted)
    # col 8: s,p,d,f etc for upper level (or X), see fdamp
    # col 9: same for lower level
    # col 10: equivalent width, when needed (abundance determination in eqwidt run)
    # col 11: error in eqw
    # col 12: (in quotes) some text describing levels or whatever you like to include

    # there could be a comma separating tokens (and fortran would parse), but I've never seen it.
    toks = split(line)

    log_gf = parse(Float64, toks[3]) 
    wl = air_to_vacuum(parse(Float64, toks[1])*1e-8)
    gamma_rad = parse(Float64, toks[6])
    if gamma_rad == 0 || gamma_rad == 1
        gamma_rad = Korg.approximate_radiative_gamma(wl, log_gf)
    end

    # if toks[7] is present, but gamma_stark is skipped, it will be the l for the upper level.
    stark_log_gamma = if length(toks) < 7 || isnothing(tryparse(Float64, toks[7]))
        missing
    else
        tentotheOrMissing(tryparse(Float64, toks[7]))
    end
    fdamp = parse(Float64, toks[4])
    if 0 < fdamp < 20
        error("fdamp parameter ($fdamp) is an enhancement factor for the damping constant, which is not supported by Korg. Please open an issue or get in contact if this is a problem for you.")
    end
    wltrans = vacuum ? identity : air_to_vacuum
    Line(wltrans(parse(Float64, toks[1])*1e-8),
         log_gf + Δloggf,
         species, 
         parse(Float64, toks[2]), 
         gamma_rad,
         stark_log_gamma,
         fdamp)
end
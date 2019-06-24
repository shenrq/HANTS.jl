#!/usr/bin/env julia
# -*- coding: utf-8 -*-
"""
module HANTS

Converted from MATLAB

https://mabouali.wordpress.com/projects/harmonic-analysis-of-time-series-hants/

"""
module HANTS
using LinearAlgebra

export hants, reconstruct, apply, reconstructimage

"""
    hants(ni, nb, nf, y, ts, HiLo, low, high, fet, dod, δ)

# HANTS processing

Wout Verhoef
NLR, Remote Sensing Dept.
June 1998

Converted to MATLAB:
Mohammad Abouali (2011) (BSD 2-Clause)

Converted from MATLAB to Julia:
Shen Ruoque (2019)

## Modified:

Apply suppression of high amplitudes for near-singular case by
adding a number δ to the diagonal elements of matrix A,
except element (1,1), because the average should not be affected.

Output of reconstructed time series in array yr June 2005.

Change call and input arguments to accommodate a base period length (nb).
All frequencies from 1 (base period) until nf are included.

# Parameters

## Inputs:
- `nb`   : length of the base period, measured in virtual samples
           (days, dekads, months, etc.)
- `nf`   : number of frequencies to be considered above the zero frequency
- `y`    : array of input sample values (e.g. NDVI values)
- `ts`   : array of size ni of time sample indicators (indicates virtual sample number
           relative to the base period); numbers in array ts maybe greater than nb.
           If no aux file is used (no time samples),
           we assume ts(i) = i, where i = 1, ..., ni
- `HiLo` : 2-character string indicating rejection of high or low outliers
- `low`  : valid range minimum
- `high` : valid range maximum (values outside the valid range are rejeced right away)
- `fet`  : fit error tolerance (points deviating more than fet from curve fit are rejected)
- `dod`  : degree of overdeterminedness (iteration stops if number of points reaches the
           minimum required for curve fitting, plus dod). This is a safety measure
- `δ`    : small positive number (e.g. 0.1) to suppress high amplitudes

## Outputs:

- `amp`   : returned array of amplitudes, first element is the average of the curve
- `φ`     : returned array of phases, first element is zero
- `yr`    : array holding reconstructed time series
"""
function hants(
    nb, nf, y::AbstractArray{T,1}, ts, HiLo, low, high, fet, dod, δ
) where {T<:AbstractFloat}

    ni = length(y)
    nr = min(2nf+1, ni)
    mat = zeros(T, nr, ni)
    amp = zeros(T, nf+1)
    φ = zeros(T, nf+1)
    yr  = zeros(T, ni)

    if HiLo == "Hi" || HiLo == "High"
        sHiLo = -1
    elseif HiLo == "Lo" || HiLo == "Low"
        sHiLo = 1
    else
        sHiLo = 0
    end
    noutmax = ni - nr - dod
    dg = 180.0 / π
    mat[1, :] .= 1.0

    ang = 2 * (0:nb-1) / nb
    cs = cospi.(ang); sn = sinpi.(ang)
    for i = 1:nf
        for j = 1:ni
            index = 1 + mod(i * (ts[j] - 1), nb)
            mat[2i  , j] = cs[index]
            mat[2i+1, j] = sn[index]
        end
    end

    p = ones(ni)
    p[(y .< low) .| (y .> high)] .= 0
    nout = sum(p .== 0)

    if nout > noutmax return end

    ready = false; nloop = 0; nloopmax = ni
    local za, zr

    while (!ready) && (nloop < nloopmax)
        nloop += 1
        za = mat * (p .* y)

        A = mat * diagm(0=>p) * mat'
        A += diagm(0=>ones(nr)) * δ
        A[1, 1] -= δ
        zr = A \ za

        yr = mat' * zr
        diffvec = sHiLo * (yr - y)
        err = p .* diffvec

        rankvec = sortperm(err)

        maxerr = diffvec[Int(rankvec[ni])]
        ready = maxerr ≤ fet || nout == noutmax

        if !ready
            i = ni; j = rankvec[i]
            while p[j] * diffvec[j] > 0.5maxerr && nout < noutmax
                p[j] = 0; nout += 1; i -= 1; j = rank(i)
            end
        end
    end

    amp[1] = zr[1]
    φ[1] = 0.0

    push!(zr, 0.0)

    i = 2:2:nr
    ifr = Int.((i .+ 2) ./ 2)
    ra = zr[i]; rb = zr[i.+1]
    amp[ifr] = sqrt.(ra.*ra .+ rb.*rb)
    phase = atan.(rb, ra) .* dg
    [phase[j] += 360.0 for j in eachindex(phase) if phase[j] < 0]
    φ[ifr] = phase

    amp, φ, yr
end

hants(nb, nf, y::AbstractArray{<:Integer,1}, ts, HiLo, low, high, fet, dod, δ) = hants(
    nb, nf, convert(Vector{Float64}, y), ts, HiLo, low, high, fet, dod, δ
)

"""
    reconstruct(amp, φ, nb)

Comput reconstructed time series.
"""
function reconstruct(amp, φ, nb)
    nf = maximum(size(amp))

    y = zeros(nb)
    a_coef = @. amp * cospi(φ / 180)
    b_coef = @. amp * sinpi(φ / 180)
    for i = 1:nf
        tt = @. (i - 1) * 2 * (0:nb-1) / nb
        y .+= a_coef[i] .* cospi.(tt) .+ b_coef[i] .* sinpi.(tt)
    end
    y
end

function apply(
    y::AbstractArray{T,N}, nb, nf, fet, dod, HiLo, low, high, δ
) where {T<:AbstractFloat,N}
    if N ≠ 3 error("Input data must be three dimensional [time, lat, lon]") end
    ni, ny, nx = size(y)

    y_out = zeros(T, ni, ny, nx)
    amp = zeros(T, nf+1, ny, nx)
    φ = zeros(T, nf+1, ny, nx)
    ts = 1:ni

    for sample = 1:nx
        for line = 1:ny
            data = y[:, line, sample]
            if sum(isnan.(data)) ≠ ni
                data[isnan.(data)] = low - 1.0
                amp[:, line, sample], φ[:, line, sample], y_out[:, line, sample] = hants(
                    nb, nf, data, ts, HiLo, low, high, fet, dod, δ
                )
            end
        end
    end
    y_out, amp, φ
end

apply(y::AbstractArray{<:Integer}, nb, nf, fet, dod, HiLo, low, high, δ) = apply(
    convert(Array{Float64}, y), nb, nf, fet, dod, HiLo, low, high, δ
)

function reconstructimage(amp::AbstractArray{<:AbstractFloat,N}, φ, nb) where N
    if N ≠ 3 error("amp and φ must be three dimensional [nf, lat, lon]") end
    ni, ny, nx = size(amp)

    data = zeros(nb, ny, nx)

    for sample = 1:nx
        for line = 1:ny
            amp_pixel = amp[:, line, sample]
            φ_pixel = φ[:, line, sample]
            data[:, line, sample] = reconstruct(amp_pixel, φ_pixel, nb)
        end
    end
    data
end

reconstructimage(amp::AbstractArray{<:Integer}, φ, nb) = reconstructimage(
    convert(Array{Float64}, amp), φ, nb
)

end # module HANTS


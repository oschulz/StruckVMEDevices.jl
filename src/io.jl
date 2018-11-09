# This file is a part of SIS3316.jl, licensed under the MIT License (MIT).

using Compat


abstract type DecompessIO end


Base.open(filename::AbstractString, ::Type{DecompessIO}) = begin
    if endswith(filename, ".gz")
        open(`gzip -d -c $filename`, "r", STDOUT)[1]
    elseif endswith(filename, ".bz2")
        try
            open(`pbzip2 -d -c $filename`, "r", STDOUT)[1]
        catch
            info("pbzip2 doesn't seem to be available, falling back to standard bzip2")
            open(`bzip2 -d -c $filename`, "r", STDOUT)[1]
        end
    elseif endswith(filename, ".xz")
        open(`xz -d -c $filename`, "r", STDOUT)[1]
    else
        open(filename, "r")
    end
end

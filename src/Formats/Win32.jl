getcha(cf) = (f = open(cf, "r"); F = readlines(f); close(f); return F)

function get_netStr(orgID,netID)
  fname = string(Pkg.dir(),"/SeisIO/src/FileFormats/jpcodes.csv")
  isfile(fname) || return "Unknown"
  nets = readdlm(fname, ';')
  i = find((nets[:,1].==orgID).*(nets[:,2].==netID))
  if isempty(i)
    return "Unknown"
  else
    return nets[i[1],:]
  end
end

# stupid, but effective
function int4_2c(s::Array{Int32,1})
  p = map(Int32, [-8,4,2,1])
  return dot(p, s[1:4]), dot(p, s[5:8])
end

function win32dict(Nh::UInt16, cinfo::String, hexID::String, StartTime::Float64, orgID::String, netID::String)
  k = Dict{String,Any}()
  k["hexID"] = hexID
  k["orgID"] = orgID
  k["netID"] = netID
  k["netName"] = get_netStr(orgID,netID)
  k["locID"] = @sprintf("%i%i", parse(orgID), parse(netID))
  parse(k["locID"]) > 99 && (warn(string("hexID = ", hexID, "locID > 99, loc code can't be set.")); k["locID"] = "")
  k["data"] = Array{Int32,1}()
  k["OldTime"] = 0
  k["seisSum"] = 0
  k["seisN"] = 0
  k["seisNN"] = 0
  k["startTime"] = StartTime
  k["gapStart"] = Array{Int64,1}(0)
  k["gapEnd"] = Array{Int64,1}(0)
  k["fs"] = Float32(Nh)
  c = split(cinfo)
  k["scale"] = parse(c[13]) / (parse(c[8]) * 10^(parse(c[12])/20))
  k["lineDelay"] = Float32(parse(c[3])/1000)
  k["unit"] = c[9]
  k["fc"] = Float32(1/parse(c[10]))
  k["hc"] = Float32(parse(c[11]))
  k["loc"] = [parse(c[14]), parse(c[15]), parse(c[16])]
  k["pCorr"] = parse(Float32, c[17])
  k["sCorr"] = parse(Float32, c[18])
  # A comment column isn't strictly required by the win format specs
  k["comment"] = length(c) > 18 ? c[19] : ""
  return k
end

function getcid(Chans, ch)
  for i = 1:1:length(Chans)
    L = split(Chans[i])
    if L[1] == ch
      return i, join(L[4:5],'.')
    end
  end
  return -1, ""
end

"""
    S = r_win32(filestr, chanfile)

Read all win32 data matching string pattern `filestr`, with corresponding
channel file `chanfile`, into dictionary S. Keys correspond to win32


"""
function r_win32(filestr::String, cf::String; v=false)
  Chans = getcha(cf)
  seis = Dict{String,Any}()
  files = lsw(filestr)
  nf = 0
  for fname in files
    v && println("Processing ", fname)
    fid = open(fname, "r")
    skip(fid, 4)
    while !eof(fid)
      # Start time: matches file info despite migraine-inducing nesting
      stime = DateTime(bytes2hex(read(fid, UInt8, 8)), "yyyymmddHHMMSSsss")
      NewTime = Dates.datetime2unix(stime)
      skip(fid, 4)
      lsecb = bswap(read(fid, UInt32))
      y = 0

      while y < lsecb
        orgID = bytes2hex(read(fid, UInt8, 1))
        netID = bytes2hex(read(fid, UInt8, 1))
        hexID = bytes2hex(read(fid, UInt8, 2))
        c = string(bits(read(fid, UInt8)),bits(read(fid, UInt8)))
        C = parse(UInt8, c[1:4], 2)
        N = parse(UInt16, c[5:end], 2)
        x = Array{Int32,1}(N)
        Nh = copy(N)

        # Increment bytes read (this file), decrement N if not 4-bit
        if C == 0
          B = N/2
        else
          N -= 1
          B = C*N
        end
        y += (10 + B)

        c, id = getcid(Chans, hexID)
        haskey(seis, id) || (seis[id] = win32dict(Nh, Chans[c], hexID, NewTime, orgID, netID))
        x[1] = bswap(read(fid, Int32))

        if C == 0
          V = read(fid, UInt8, Int(N/2))
          for i = 1:1:length(V)
            x1,x2 = int4_2c(map(Int32, bits(V[i]).data - 0x30))
            if i < N/2
              x[2*i:2*i+1] = [x1 x2]
            else
              x[N] = x1
            end
          end
          N+=1
        elseif C == 1
          x[2:end] = read(fid, Int8, N)
        elseif C == 3
          V = read(fid, UInt8, 3*N)
          for i = 1:1:N
            xi = join([bits(V[3*i]),bits(V[3*i-1]),bits(V[3*i-2])])
            x[i+1] = parse(Int32, xi, 2)
          end
        else
          fmt = (C == 2 ? Int16 : Int32)
          V = read(fid, fmt, N)
          x[2:end] = [bswap(i) for i in V]
        end
        # cumsum doesn't work on int32...?
        [x[i] += x[i-1] for i in 2:1:length(x)]
        # Account for time gaps
        gap = NewTime - seis[id]["OldTime"] - 1
        if ((gap > 0) && (seis[id]["OldTime"] > 0))
          warn(@sprintf("Time gap detected! (%.1f s at %s, beginning %s)",
                gap, id,  Dates.unix2datetime(seis[id]["OldTime"])))
          push!(seis[id]["gapStart"], 1+length(seis[id]["data"]))
          P = seis[id]["fs"]*gap
          seis[id]["seisNN"] += P
          append!(seis[id]["data"], zeros(Int32, Int(P)))
          push!(seis[id]["gapEnd"], length(seis[id]["data"]))
        end

        # Update times
        seis[id]["OldTime"] = NewTime
        append!(seis[id]["data"], x)
        seis[id]["seisSum"] += sum(x)
        seis[id]["seisN"] += Nh
      end
    end
    close(fid)
    nf += 1
  end
  # Fill data gaps
  for i in collect(keys(seis))
    J = length(seis[i]["gapStart"])
    if J > 0
      av = round(Int32, seis[i]["seisSum"]/seis[i]["seisN"])
      for j = 1:1:J
        si = seis[i]["gapStart"][j]
        ei = seis[i]["gapEnd"][j]
        seis[i]["data"][si:ei] = av
      end
      warn(@sprintf("Replaced %i missing data in %s with %0.2f",
            seis[i]["seisNN"], i, av))
    end
    for j in ("seisN", "seisNN", "seisSum", "OldTime", "gapStart", "gapEnd")
      delete!(seis[i],j)
    end
  end
  seis["fname"] = filestr
  seis["cfile"] = cf
  return seis
end

function win32toseis(D = Dict{String,Any}())
  K = sort(collect(keys(D)))
  seis = SeisData()
  for k in K
    !isa(D[k],Dict{String,Any}) && continue
    fs = D[k]["fs"]
    units = D[k]["unit"]
    (net, sta, chan_stub) = split(k, '.')
    fc = D[k]["fc"]
    hc = D[k]["hc"]
    b = getbandcode(fs, fc = fc)                  # Band code
    g = 'H'                                       # Gain code
    c = chan_stub[1]                              # Channel code
    c == 'U' && (c = 'Z')                         # Nope
    cha = string(b,g,c)
    loc = D[k]["locID"]
    # Location codes are based on Japanese numeric network codes
    # This is done because the SEED standard currently only has one Japanese
    # network listed; JMA, under code "JP"

    id = join(["JP", sta, loc, cha], '.')
    # There will be issues here; Japanese files use NIED or local station
    # names, which don't necessarily match international station names. See e.g.
    # http://data.sokki.jmbsc.or.jp/cdrom/seismological/catalog/appendix/apendixe.htm
    # for an example of the (lack of) correspondence

    x = map(Float64, D[k]["data"].*D[k]["scale"])
    t = [1 round(Int,D[k]["startTime"]/μs); length(D[k]["data"]) 0]
    src = "win32"
    notes = [string(now, "  Record source: ", D[k]["netName"]);
             string(now, "  Location comment: ", D[k]["comment"]);
             string(now, "  Read from file ", D["fname"]);
             string(now, "  Channel file ", D["cfile"])]
    misc = Dict{String,Any}()
    if units == "m/s"
      resp = fctopz(fc, hc=hc, units=units)
    else
      resp = Array{Complex{Float64},2}(0,2)
    end
    [misc[sk] = D[k][sk] for sk in ("hexID", "orgID", "netID", "fc", "hc", "pCorr", "sCorr", "lineDelay", "comment")]

    seis += SeisChannel(id=id,
      name=k,
      x=x,
      t=t,
      gain=1.0,
      fs=fs,
      units=units,
      loc=[D[k]["loc"]; 0; 0],
      misc=misc,
      src=src,
      resp=resp,
      notes=notes)
  end
  return seis
end

"""
    S = readwin32(filestr, chanfile)

Read all win32 data matching string pattern `filestr`, with corresponding
channel file `chanfile`; return a seisdata object S.

"""
readwin32(f::String, c::String; v=false::Bool) = (
  D = r_win32(f, c, v=v); return(win32toseis(D)))
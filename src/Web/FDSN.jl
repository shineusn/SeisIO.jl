# =============================================================================
# No export
function LightXML_plunge(xtmp::Array{LightXML.XMLElement,1}, str::AbstractString)
  xtmp2 = Array{LightXML.XMLElement,1}()
  for i=1:length(xtmp)
    append!(xtmp2, get_elements_by_tagname(xtmp[i], str))
  end
  return xtmp2
end

function LightXML_find(xtmp::Array{LightXML.XMLElement,1}, str::String)
  S = split(str, "/")
  for i=1:length(S)
    xtmp = LightXML_plunge(xtmp, S[i])
  end
  return xtmp
end
LightXML_find(xdoc::LightXML.XMLDocument, str::String) = LightXML_find([LightXML.root(xdoc)], str)
LightXML_find(xtmp::LightXML.XMLElement, str::String) = LightXML_find([xtmp], str)

function LightXML_str!(v::String, x::LightXML.XMLElement, s::String)
  Q = LightXML_find(x, s)
  if isempty(Q) == false
    v = content(Q[1])
  end
  return v
end
LightXML_float!(v::Float64, x::LightXML.XMLElement, s::String) = parse(Float64, LightXML_str!(string(v), x, s))

function FDSN_event_xml(string_data::String)
  xevt = LightXML.parse_string(string_data)
  events = LightXML_find(xevt, "eventParameters/event")
  N = length(events)
  id = Array{Int64,1}(N)
  ot = Array{DateTime,1}(N)
  loc = Array{Float64,2}(3,N)
  mag = Array{Float32,1}(N)
  msc = Array{Char,2}(2,N)
  for (i,evt) in enumerate(events)
    try
      id[i] = parse(Int64, String(split(attribute(evt, "publicID"),'=')[2]))
    catch
      id[i] = 0
    end

    ot[i] = DateTime(LightXML_str!("1970-01-01T00:00:00", evt, "origin/time/value"))
    loc[1,i] = LightXML_float!(0.0, evt, "origin/latitude/value")
    loc[2,i] = LightXML_float!(0.0, evt, "origin/longitude/value")
    loc[3,i] = LightXML_float!(0.0, evt, "origin/depth/value")/1.0e3
    mag[i] = Float32(LightXML_float!(-5.0, evt, "magnitude/mag/value"))

    msc[:,i] = ['?'; ' ']
    tmp = LightXML_str!("--", evt, "magnitude/type")
    if isempty(tmp)
      msc[1:2,i] = ['?',' ']
    elseif tmp != "--"
      if lowercase(tmp[1]) != 'm'
        msc[1,i] = tmp[1]
        if length(tmp) > 1
          msc[1,i] = tmp[2]
        end
      elseif length(tmp) > 1
        msc[1,i] = tmp[2]
        if length(tmp) > 2
          msc[2,i] = tmp[3]
        end
      end
    end
  end
  return (id, ot, loc, mag, msc)
end

function FDSN_sta_xml(string_data::String)
  xroot = LightXML.parse_string(string_data)
  N = length(LightXML_find(xroot, "Network/Station/Channel"))

  ID    = Array{String,1}(N)
  NAME  = Array{String,1}(N)
  LOC   = Array{Array{Float64,1}}(N)
  UNITS = collect(Main.Base.Iterators.repeated("unknown",N))
  GAIN  = Array{Float64,1}(N)
  RESP  = Array{Array{Complex{Float64},2}}(N)
  MISC  = Array{Dict{String,Any}}(N)
  for i = 1:N
    MISC[i] = Dict{String,Any}()
  end
  y = 0

  xnet = LightXML_find(xroot, "Network")
  for net in xnet
    nn = attribute(net, "code")

    xsta = LightXML_find(net, "Station")
    for sta in xsta
      ss = attribute(sta, "code")
      loc_tmp = zeros(Float64, 3)
      loc_tmp[1] = LightXML_float!(0.0, sta, "Latitude")
      loc_tmp[2] = LightXML_float!(0.0, sta, "Longitude")
      loc_tmp[3] = LightXML_float!(0.0, sta, "Elevation")/1.0e3
      name = LightXML_str!("0.0", sta, "Site/Name")

      xcha = LightXML_find(sta, "Channel")
      for cha in xcha
        y += 1
        czs = Array{Complex{Float64},1}()
        cps = Array{Complex{Float64},1}()
        ID[y]               = join([nn, ss, attribute(cha,"locationCode"), attribute(cha,"code")],'.')
        NAME[y]             = identity(name)
        LOC[y]              = zeros(Float64,5)
        LOC[y][1:3]         = copy(loc_tmp)
        LOC[y][4]           = LightXML_float!(0.0, cha, "Azimuth")
        LOC[y][5]           = LightXML_float!(0.0, cha, "Dip") - 90.0
        GAIN[y]             = 1.0
        MISC[y]["normfreq"] = 1.0

        xresp = LightXML_find(cha, "Response")
        if !isempty(xresp)
          MISC[y]["normfreq"] = LightXML_float!(0.0, xresp[1], "InstrumentSensitivity/Frequency")
          GAIN[y]             = LightXML_float!(1.0, xresp[1], "InstrumentSensitivity/Value")
          UNITS[y]            = LightXML_str!("unknown", xresp[1], "InstrumentSensitivity/InputUnits/Name")

          xstages = LightXML_find(xresp[1], "Stage")
          for stage in xstages
            pz = LightXML_find(stage, "PolesZeros")
            for j = 1:length(pz)
              append!(czs, [complex(LightXML_float!(0.0, z, "Real"), LightXML_float!(0.0, z, "Imaginary")) for z in LightXML_find(pz[j], "Zero")])
              append!(cps, [complex(LightXML_float!(0.0, p, "Real"), LightXML_float!(0.0, p, "Imaginary")) for p in LightXML_find(pz[j], "Pole")])
            end
          end
        end
        NZ = length(czs)
        NP = length(cps)
        if NZ < NP
          for z = NZ+1:NP
            push!(czs, complex(0.0,0.0))
          end
        end
        RESP[y] = hcat(czs,cps)
      end
    end
  end
  return ID, LOC, UNITS, GAIN, RESP, NAME, MISC
end
# =============================================================================

"""
FDSNget: CLI for FDSN time-series data requests.

    S = FDSNget(CHAN_IDS, s=TS, t=TE, to=TO, w=false, y=true)

Retrieve data from an FDSN HTTP server for the channels in CHAN_IDS, formatted NET.STA.LOC.CHA; leave `LOC` field blank to set to "--" (e.g. "UW.ELK..EHZ"). Returns a SeisData struct. See FDSN documentation at http://service.iris.edu/fdsnws/dataselect/1/

## Channel ID specification
Type `?chanspec` for details

## Possible Keywords
* `s`: Start time (type ?parsetimewin for details)
* `t`: End time (type ?parsetimewin for details)
* `to`: Timeout in seconds
* `q`: Quality code (FDSN/IRIS). Caution: `q='R'` fails with many queries
* `w`: Write raw download directly to file
* `y`: Synchronize start and end times of channels and fill time gaps

### Example
* `S = FDSNget("UW.SEP..EHZ,UW.SHW..EHZ,UW.HSR..EHZ", t=(-600))`: Get the last 10 minutes of data from vertical-component short-period stations SEP, SHW, and HSR, Mt. St. Helens, USA.

### Some FDSN Servers
* Incorporated Research Institutions for Seismology, US: http://service.iris.edu/fdsnws/
* Réseau Sismologique et Géodesique Français, FR: http://ws.resif.fr/fdsnws/
* Northern California Earthquake Data Center, US: http://service.ncedc.org/fdsnws/
* GFZ Potsdam, DE: http://geofon.gfz-potsdam.de/fdsnws/
"""
function FDSNget(C::Array{String,2};
  src="IRIS"::String,
  q='B'::Char,
  s=0::Union{Real,DateTime,String},
  t=(-300)::Union{Real,DateTime,String},
  v=0::Int,
  w=false::Bool,
  y=false::Bool,
  si=true::Bool,
  to=30::Real)

  seis = SeisData()
  minreq!(C)
  v > 1 && println(STDOUT, "Most compact request form = ", C)
  d0, d1 = parsetimewin(s, t)
  uhead = get_uhead(src)
  for j = 1:size(C,1)
    utail = build_stream_query(C[j,:], d0, d1)
    data_url = string(uhead, "dataselect/1/query?quality=", q, "&", utail)
    v > 0 && println(STDOUT, "data url = ", data_url)

    # Get data
    R = get(data_url, timeout=to, headers=webhdr())
    if R.status == 200
      w && savereq(R.data, "mseed", C[j,1], C[j,2], C[j,3], C[j,4], d0, d1, string(q))
      S = parsemseed(IOBuffer(R.data), false, v)

      # Detailed source logging
      S.src = collect(Main.Base.Iterators.repeated(data_url, S.n))

      # Automatically incorporate station information from web XML retrieval
      if si
        station_url = string(uhead, "station/1/query?level=response&", utail)
        v > 1 && println(STDOUT, "station url = ", station_url)
        R = get(station_url, timeout=to, headers=webhdr())
        if R.status == 200
          (ID, LOC, UNITS, GAIN, RESP, NAME, MISC) = FDSN_sta_xml(String(IOBuffer(R.data)))
          for i = 1:S.n
            k = findid(S.id[i], ID)
            k == 0 && continue
            S.loc[i]    = LOC[k]
            S.units[i]  = UNITS[k]
            S.gain[i]   = GAIN[k]
            S.resp[i]   = RESP[k]
            S.name[i]   = NAME[k]
            merge!(S.misc[i], MISC[k])
          end
        end
      end
      seis += S
    end
  end
  if y
    sync!(seis, s=d0, t=d1)
  end
  return seis
end

FDSNget(S::String;
  src="IRIS"::String,
  q='B'::Char,
  s=0::Union{Real,DateTime,String},
  t=600::Union{Real,DateTime,String},
  v=0::Int,
  w=false::Bool,
  y=false::Bool,
  si=true::Bool,
  to=30::Real) = FDSNget(parse_chstr(S, fdsn=true), src=src, q=q, s=s, t=t, v=v, w=w, y=y, si=si, to=to)

FDSNget(S::Array{String,1};
  src="IRIS"::String,
  q='B'::Char,
  s=0::Union{Real,DateTime,String},
  t=600::Union{Real,DateTime,String},
  v=0::Int,
  w=false::Bool,
  y=false::Bool,
  si=true::Bool,
  to=30::Real) = FDSNget(parse_charr(S, fdsn=true), src=src, q=q, s=s, t=t, v=v, w=w, y=y, si=si, to=to)

"""
    H = FDSNevq(t)

Multi-server query for the events with the closest origin time to `t`. `t`
should be a string formatted YYYY-MM-DDThh:mm:ss with times given in UTC
(e.g. "2001-02-08T18:54:32"). Returns a SeisHdr array.

Incomplete string queries are read to the nearest fully specified time
constraint, e.g., FDSNevq("2001-02-08") returns the nearest event to 2001-02-08T00:00:00
UTC. If no event is found on any server within one day of the specified search
time, FDSNevq exits with an error.

Additional arguments can be passed at the command line for more fine-grained control:
* `w=N`: search `N` seconds around `t` for events. (default: 86400)
* `x=true`: treat `t` as exact to one second. Overrides `w`.
* `mag=[MIN_MAG MAX_MAG]`: restrict queries to `MIN_MAG` ≤ m ≤ `MAX_MAG`. (default: [6.0 9.9])
* `n=N`: Return `N` events, rather than 1.
* `lat=[LAT_MIN LAT_MAX]`: Specify a latitude range in decimal degrees with North as positive.
* `lon=[LON_MIN LON_MAX]`: Specify a longitude range in decimal degrees with East as positive.
* `dep=[DEP_MIN DEP_MAX]`: Specify a depth range in km.
* `src=SRC`: Only query server **SRC**. Specify as a string. Type `?FDSNget` for servers and meanings.
"""
function FDSNevq(ts::String;
  dep=[-30.0 700.0]::Array{Float64,2},
  lat=[-90.0 90.0]::Array{Float64,2},
  lon=[-180.0 180.0]::Array{Float64,2},
  mag=[6.0 9.9]::Array{Float64,2},
  n=1::Int,
  src="IRIS"::String,
  to=30::Real,
  w=600.0::Real,
  x=false::Bool,
  v=0::Int)
  if x
    w = 1.0
  end

  # Determine time window
  if length(ts) <= 14
    ts0 = string(ts[1:4],"-",ts[5:6],"-",ts[7:8],"T",ts[9:10],":",ts[11:12])
    if length(ts) > 12
      ts = string(ts0, ":", ts[13:14])
    else
      ts = string(ts0, ":00")
    end
  end
  ts = d2u(DateTime(ts))
  s = string(u2d(ts-w))
  t = string(u2d(ts+w))
  tsi = round(Int64, ts*sμ)

  # Do multi-server query (not tested)
  if lowercase(src) == "all"
    sources = ["IRIS", "NCEDC", "GFZ"]
  else
    sources = split(src,",")
  end
  catalog = Array{SeisHdr,1}()
  ot = Array{Int64,1}()
  for k in sources
    url = string(get_uhead(String(k)), "event/1/query?",
    "starttime=", s, "&endtime=", t,
    "&minlat=", lat[1], "&maxlat=", lat[2],
    "&minlon=", lon[1], "&maxlon=", lon[2],
    "&mindepth=", dep[1], "&maxdepth=", dep[2],
    "&minmag=", mag[1], "&maxmag=", mag[2],
    "&format=xml")
    v >0 && println(STDOUT, url)
    R = get(url, timeout=to, headers=webhdr())
    if R.status == 200
      v > 1 && println(STDOUT, String(IOBuffer(R.data)))
      (id, ot_tmp, loc, mm, msc) = FDSN_event_xml(String(IOBuffer(R.data)))
      for i = 1:length(id)
        eh = SeisHdr(id=id[i], ot=ot_tmp[i], loc=loc[:,i], mag=(mm[i], msc[1,i], msc[2,i]), src=url)
        push!(catalog, eh)
        push!(ot, round(Int64, d2u(eh.ot)*sμ))
      end
      v > 1 && println(STDOUT, "catalog = ", catalog)
    end
  end
  if isempty(ot)
    return catalog
  else
    k = sortperm(abs.(ot.-tsi))
    n0 = min(length(k),n)
    n0 < n && warn(string("Catalog only contains ", n0, " events (original request was n=", n,")"))
    return catalog[k[1:n0]]
  end
end

"""
    S = FDSNsta(CF)

Retrieve station/channel info for formatted parameter file (or string) `CF` as an empty SeisData structure.

See also: `?SeedLink` for keyword options, `?chanspec` for channel ID specifications.
"""
function FDSNsta(CC::Array{String,2};
  src="IRIS"::String,
  st="2011-01-08T00:00:00"::Union{Real,DateTime,String},
  et="2011-01-09T00:00:00"::Union{Real,DateTime,String},
  to=60::Real,
  v=0::Int)

  d0, d1 = parsetimewin(st, et)
  uhead = string(get_uhead(src), "station/1/query?")
  seis = SeisData()
  for j = 1:size(CC,1)
    utail = build_stream_query(CC[j,:], d0, d1) * "&format=text&level=channel"
    sta_url = string(uhead, utail)
    v > 0 && println(STDOUT, "Retrieving station data from URL = ", sta_url)
    R = get(sta_url, timeout=to, headers=webhdr())
    if R.status == 200
      ch_data = readstring(R)
      v > 0 && println(STDOUT, ch_data)
      ch_data = split(ch_data,"\n")
      for n = 2:size(ch_data,1)-1
        C = split(ch_data[n],"|")
        try
          #Network | Station | Location | Channel
          ID = @sprintf("%s.%s.%s.%s",C[1],C[2],C[3],C[4])
          NAME = ID
          LOC = collect([parse(Float64, C[5])
          parse(Float64, C[6])
          parse(Float64, C[7])+parse(Float64, C[8])
          parse(Float64, C[9])
          90.0 - parse(Float64, C[10])])

          # Strictly speaking this is only accurate for passive velocity sensors
          RESP = fctopz(parse(Float64, C[13]))
          MISC = Dict{String,Any}(
            "SensorDescription" => String(C[11]),
            "SensorStart" => String(C[16]),
            "SensorEnd" => String(C[17])
          )
          s = SeisChannel(name=NAME, id=ID, fs=parse(Float64, C[15]),
          gain=parse(Float64, C[12]), loc=LOC, misc=MISC, resp=RESP, src=sta_url,
          units=String(C[14]))

          note!(s, string("+src: FDSNsta ", src))
          seis += s
        catch err
          ID = @sprintf("%s.%s.%s.%s",C[1],C[2],C[3],C[4])
          warn("Failed to parse ", ID,"; caught $err. Maybe bad or missing parameter(s) returned by server.")
          if v > 0
            println(STDOUT, "Text dump of bad record line follows:")
            println(STDOUT, ch_data[n])
          end
        end
      end
    end
  end
  return seis
end
function FDSNsta(C::String;
  st="2011-01-08T00:00:00"::Union{Real,DateTime,String},
  et="2011-01-09T00:00:00"::Union{Real,DateTime,String},
  src="IRIS"::String,
  to=60::Real,
  v=0::Int)

  Q = parse_chstr(C, fdsn=true)
  v > 0 && println(STDOUT, "station query =", Q)
  S = FDSNsta(Q, src=src, st=st, et=et, to=to, v=v)
  return S
end

"""
    FDSNevt(evt::String, cc::String)

Get trace data for event `evt`, channels `cc`. Auto-filled with auxiliary functions.

See also: `FDSNevq`, `FDSNsta`, `distaz!`
"""
function FDSNevt(evt::String, cc::String;
  mag=[6.0 9.9]::Array{Float64,2},
  to=30.0::Real,
  pha="P"::String,
  spad=1.0::Real,
  epad=0.0::Real,
  v=0::Int)

  v > 0 && println(STDOUT, now(), ": request begins.")

  # Parse channel config
  Q = parse_chstr(cc)

  # Create header
  h = FDSNevq(evt, mag=mag, to=to, v=v)[1]   # Get event of interest with FDSNevq
  v > 0 && println(STDOUT, now(), ": header query complete.")

  # Create channel data
  s = h.ot                                      # Start time for FDSNsta is event origin time
  t = u2d(d2u(s) + 1.0)                         # End time is one second later
  d = FDSNsta(Q, st=s, et=t, to=to, v=v)
  v > 0 && println(STDOUT, now(), ": channels initialized.")

  # Initialize SeisEvent structure
  S = SeisEvent(hdr = h, data = d)
  v > 0 && println(STDOUT, now(), ": SeisEvent created.")
  v > 1 && println(STDOUT, S)

  # Update S with distance, azimuth
  distaz!(S)
  v > 0 && println(STDOUT, now(), ": Δ,Θ updated.")

  # Desired behavior:
  # If the phase string supplied is "all", request window is spad s before P to twice the last phase arrival
  # If a phase name is supplied, request window is spad s before that phase to epad s after next phase
  pstr = Array{String,1}(S.data.n)
  bads = falses(S.data.n)
  for i = 1:S.data.n
    pdat = get_pha(S.data.misc[i]["dist"], S.hdr.loc[3], to=to, v=v)
    if pha == "all"
      j = get_phase_start(pdat)
      s = parse(Float64,pdat[j,4]) - spad
      t = 2.0*parse(Float64,pdat[get_phase_end(pdat),4])
      S.data.misc[i]["PhaseWindow"] = string(pdat[j,3], " : Coda")
    else
      # Note: at Δ > ~90, we must use Pdiff; we can't use P
      p1 = pha
      j = findfirst(pdat[:,3].==p1)
      if j == 0
        p1 = pha*"diff"
        j = findfirst(pdat[:,3].==p1)
        if j == 0
          error(string("Neither ", pha, " nor ", pha, "diff found!"))
        else
          warn(string(pha, "diff substituted for ", pha, " at ", S.data.id[i]))
        end
      end
      s = parse(Float64,pdat[j,4]) - spad
      #(p2,t) = nextPhase(p1, pdat)
      (p2,t) = next_converted(p1, pdat)
      t += epad
      S.data.misc[i]["PhaseWindow"] = string(p1, " : ", p2)
    end
    s = string(u2d(d2u(S.hdr.ot) + s))
    t = string(u2d(d2u(S.hdr.ot) + t))
    C = FDSNget(S.data.id[i], s=s, t=t, si=false, y=false, v=v)
    v > 1 && println(STDOUT, "FDSNget output:\n", C)
    if C.n == 0
      bads[i] = true
    else
      S.data.t[i] = C.t[1]
      S.data.x[i] = C.x[1]
      S.data.notes[i] = C.notes[1]
      S.data.src[i] = C.src[1]
      v > 0 && println(STDOUT, now(), ": data acquired for ", S.data.id[i])
    end
  end
  bad = find(bads.==true)
  if !isempty(bad)
    ids = join(S.data.id[bad],',')
    warn(string("Channels ", ids, " removed (no data were found)."))
    deleteat!(S.data, bad)
  end
  return S
end

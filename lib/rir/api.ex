defmodule Rir.Api do
  @moduledoc """
  Functions that update a given context with datasets by querying the RIPEstat API

  Notes:
  - AS nrs are strings, without the AS prefix, e.g. AS42 -> "42"
  - Each API endpoint has a map stored under its own key in the context
  - Each API call has its results stored under the relevant key(s)
  - API results themselves, are always represented as a map

  """

  alias Rir.Stat

  # Helpers
  # todo
  # - [ ] decoders must check the version of the reply given
  # - [ ] decoders must check call status

  @spec decode(tuple) :: map
  defp decode({:ok, {%{name: "announced-prefixes", status: :ok}, data}}) do
    # Announced-prefixes is a list of prefixes
    %{prefixes: data["prefixes"] |> Enum.map(&Map.get(&1, "prefix"))}
  end

  defp decode({:ok, {%{name: "as-routing-consistency", status: :ok}, data}}) do
    # notes
    # - irr_sources is a "-" and not a list, if the prefix is not in whois
    # AS-routing-consistency
    #   peers => %{peer => {:imports, bgp?, whois?, :exports, bgp?, whois?}}
    #   prefixes => %{prefix => {bgp?, whois?, authorities}
    prefixes = map_tuples(data["prefixes"], ["prefix", "in_bgp", "in_whois", "irr_sources"])
    exports = map_tuples(data["exports"], ["peer", "in_bgp", "in_whois"])
    imports = map_tuples(data["imports"], ["peer", "in_bgp", "in_whois"])

    peers =
      Map.merge(imports, exports, fn _peer, {a, b}, {c, d} -> {:imports, a, b, :exports, c, d} end)

    %{prefixes: prefixes, peers: peers}
  end

  defp decode({:ok, {%{name: "as-overview", status: :ok}, data}}) do
    # As-overiew
    data
  end

  defp decode({:ok, {%{name: "bgp-state", status: :ok}, data}}) do
    # Bgp-state
    data["bgp_state"]
    |> list_tuples(["target_prefix", "path"])
    |> Enum.map(fn {pfx, as_path} -> {pfx, Enum.take(as_path, -2) |> hd()} end)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn {pfx, asn}, acc ->
      Map.update(acc, pfx, [asn], fn asns -> [asn | asns] end)
    end)
  end

  defp decode({:ok, {%{name: "network-info", status: :ok}, data}}) do
    # Network-info
    asn = data["asns"] |> List.first()
    %{asn: asn, asns: data["asns"], prefix: data["prefix"]}
  end

  defp decode({:ok, {%{name: "ris-prefixes", status: :ok}, data}}) do
    # Ris-prefixes
    prefixes = data["prefixes"]

    %{
      originating: prefixes["v4"]["originating"] ++ prefixes["v6"]["originating"],
      transiting: prefixes["v4"]["transiting"] ++ prefixes["v6"]["transiting"]
    }
  end

  defp decode({:ok, {%{name: "rpki-validation", status: :ok}, data}}) do
    # Rpki-validation
    with status <- data["status"],
         roas <- data["validating_roas"] do
      %{
        status: Stat.to_atom(status),
        roas: list_tuples(roas, ["origin", "prefix", "max_length", "validity"])
      }
    end
  end

  defp decode({:ok, {%{name: "whois", status: :ok}, data}}) do
    # Whois
    records = Enum.map(data["records"], fn l -> list_tuples(l, ["key", "value"]) end)
    irr = Enum.map(data["irr_records"], fn l -> list_tuples(l, ["key", "value"]) end)

    %{
      autorities: data["authorities"],
      records: records,
      irr: irr
    }
  end

  defp decode({:ok, {%{name: name, status: :ok} = call, _data}}),
    # Missing decode handler
    do: %{call: call, error: "missing Rir.Api.decode/2 for api endpoint #{inspect(name)}"}

  defp decode({:error, {call, reason}}),
    # Api Error
    do: %{error: reason, call: call}

  defp list_tuples(list, keys) do
    # turn a list of maps, into a list of tuples for selected keys
    list
    |> Enum.map(fn m -> for(k <- keys, do: Map.get(m, k)) end)
    |> Enum.map(fn l -> List.to_tuple(l) end)
  end

  defp map_tuples(list, [primary | keys]) do
    # turn a list of maps, into a map of tuples
    # - primary is the unique key, different for each map
    # - keys is the list of keys whose values are presented as a tuple
    list
    |> Enum.map(fn m -> {Map.get(m, primary), for(key <- keys, do: Map.get(m, key))} end)
    |> Enum.map(fn {k, l} -> {k, List.to_tuple(l)} end)
    |> Enum.into(%{})
  end

  defp store(data, ctx, api_call, resource) do
    # store resulting data in context under resource for given API endpoint name
    Map.get(ctx, api_call, %{})
    |> Map.put(resource, data)
    |> then(fn updated -> Map.put(ctx, api_call, updated) end)
  end

  # API

  @doc """
  Stores the [announced](https://stat.ripe.net/docs/02.data-api/announced-prefixes.html)
  prefixes for given `asn`, under `ctx.announced["asn"].prefixes` as a map
  (with only one key).

  ```elixir
  %{ announced: %{
    "asn" => %{
      prefixes: ["prefix1", "prefix2", ..]
    }
  }
  ```

  """
  @spec announced(map, binary) :: map
  def announced(ctx, asn) do
    Stat.url("announced-prefixes", resource: asn)
    |> Stat.get()
    |> decode()
    |> store(ctx, :announced, asn)
  end

  @doc """
  Stores the [as-overview](https://stat.ripe.net/docs/02.data-api/as-overview.html)
  for given `asn`, under `ctx.as_overview["asn"]` as a map.

  ```
  %{ as_overview: %{
    "asn" => %{
      "announced" => boolean,
      "block" => %{
        "desc" => "...",
        "name" => "...",
        "resource" => "xxx-yyy"
      },
      "holder" => "name of organisation",
      "resource" => "number",
      "type" => "as"
    }
  }}
  ```

  """
  @spec as_overview(map, binary) :: map
  def as_overview(ctx, asn) do
    Stat.url("as-overview", resource: asn)
    |> Stat.get()
    |> decode()
    |> store(ctx, :as_overview, asn)
  end

  @doc """
  Stores the [bgp state](https://stat.ripe.net/docs/02.data-api/bgp-state.html)
  results under the `;bgp_state` key in given `ctx` for given `resource`.

  The results are processed into a map where the list of upstream neighbors seen
  in BGP are stored under the `prefix` key.

  """
  @spec bgp_state(map, binary) :: map
  def bgp_state(ctx, resource) do
    Stat.url("bgp-state", resource: resource)
    |> Stat.get()
    |> decode()
    |> store(ctx, :bgp_state, resource)
  end

  @doc """
  Stores the
  [as-routing-consistency](https://stat.ripe.net/docs/02.data-api/as-routing-consistency.html)
  for given `asn`, under `ctx.consistency["asn"]` as a map.

  ```
  %{
    consistency: %{
      "asn" => %{
        peers: %{
          asn1 => {:imports, bgp?, whois?, :exports, bgp?, whois?},
          asn2 => {:imports, bgp?, whois?, :exports, bgp?, whois?},
          ...
        },
        prefixes: %{
          "prefix/len" => {bgp?, whois?, ["authority", ...]},
          ...
        }
      }
    }
  }
  ```

  """
  @spec consistency(map, binary) :: map
  def consistency(ctx, asn) do
    Stat.url("as-routing-consistency", resource: asn)
    |> Stat.get(retry: 4)
    |> decode()
    |> store(ctx, :consistency, asn)
  end

  @doc """
  Stores the
  [network-info](https://stat.ripe.net/docs/02.data-api/network-info.html) for
  given `prefix` under `ctx.network["prefix"]` as a map.

  ```
  %{
    network: %{
      "prefix" => %{asn: "number", asns: ["number", ..], prefix: "matching-prefix"}
    }
  }
  ```

  The `prefix` given can be an address or a real prefix and the `matching-prefix`
  is the most specific match found.

  Note that the `asn` field in the map is just the first "asn" from the list of
  `asns` returned.

  """
  @spec network(map, binary) :: map
  def network(ctx, prefix) do
    Stat.url("network-info", resource: prefix)
    |> Stat.get()
    |> decode()
    |> store(ctx, :network, prefix)
  end

  @doc """
  Stores the [ris-prefixes]() for given `asn` under `:ris_prefixes`
  in given `ctx`.

  """
  @spec ris_prefixes(map, binary) :: map
  def ris_prefixes(ctx, asn) do
    Stat.url("ris-prefixes", resource: asn, list_prefixes: "true")
    |> Stat.get()
    |> decode()
    |> store(ctx, :ris_prefixes, asn)
  end

  @doc """
  Stores the
  [rpki-validation](https://stat.ripe.net/docs/02.data-api/rpki-validation.html)
  status for the given `asn` and `prefix` under `ctx.roa[{asn, prefix}]` as a
  map.

  ```elixir
  %{
    roa: %{
      {"asn", "prefix"} => %{
        roas: [{"asn", "matching-prefix", max_len, "status"}],
        status: :valid | :invalid
      }
    }
  }
  ```

  Where the "status" string can be:
  - "valid"
  - "invalid_as"
  - "invalid_len"
  - "unknown"

  """
  @spec roa(map, binary, binary) :: map
  def roa(ctx, asn, prefix) do
    Stat.url("rpki-validation", resource: asn, prefix: prefix)
    |> Stat.get()
    |> decode()
    |> store(ctx, :roa, {asn, prefix})
  end

  @doc """
  Stores the [whois](https://stat.ripe.net/docs/02.data-api/whois.html)
  information for given `resource` under `ctx.whois[resource]` as a map.

  The `resource` can be either a ASN number, IP address or IP prefix.  The
  whois records are transformed into a list of two-element tuples in the form
  of `{key, value}` without any other transformation.  Depending on the registry
  the information came from, different `{key, value}`-pairs may be listed for an
  object.

  ```elixir
  %{
    whois: %{
      "resource" => %{
        autorities: ["authority", ..],
        irr: [
          [
          {key, value},
          ...
          ],
          ;;;
        ],
        records: [
          [
            {key, value},
            ...
            {"source", "authority"}
          ],
          ...
        ]
      }
    }
  }
  ```

  """
  @spec whois(map, binary) :: map
  def whois(ctx, resource) do
    Stat.url("whois", resource: resource)
    |> Stat.get()
    |> decode()
    |> store(ctx, :whois, resource)
  end
end

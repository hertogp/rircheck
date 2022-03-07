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

  @spec decode(map) :: map
  defp decode(%{data: data, call: %{name: "announced-prefixes", status: :ok}}) do
    # Announced-prefixes is a list of prefixes
    %{prefixes: data["prefixes"] |> Enum.map(&Map.get(&1, "prefix"))}
  end

  defp decode(%{data: data, call: %{name: "as-routing-consistency", status: :ok} = _call}) do
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

  defp decode(%{data: data, call: %{name: "as-overview", status: :ok}}) do
    data
  end

  defp decode(%{data: data, call: %{name: "network-info", status: :ok}}) do
    asn = data["asns"] |> List.first()
    %{asn: asn, asns: data["asns"], prefix: data["prefix"]}
  end

  defp decode(%{data: data, call: %{name: "rpki-validation", status: :ok} = _call}) do
    # Rpki-validation
    with status <- data["status"],
         roas <- data["validating_roas"] do
      %{
        status: Stat.to_atom(status),
        roas: list_tuples(roas, ["origin", "prefix", "max_length", "validity"])
      }
    end
  end

  defp decode(%{data: data, call: %{name: "whois", status: :ok}}) do
    # Whois
    records = Enum.map(data["records"], fn l -> list_tuples(l, ["key", "value"]) end)
    irr = Enum.map(data["irr_records"], fn l -> list_tuples(l, ["key", "value"]) end)

    %{
      autorities: data["authorities"],
      records: records,
      irr: irr
    }
  end

  defp decode(%{data: _data, call: %{name: name, status: :ok} = call}),
    # api endpoint has no decoder
    do: %{call: call, error: "missing Rir.Api.decode/2 for api endpoint #{inspect(name)}"}

  defp decode(%{error: reason, call: call}),
    # api returned an error response
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
  prefixes for given `asn`, under `ctx.announced["asn"]` as a list under
  the `prefixes` key.

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
          "prefix/len" => {bgp?, whois? ["authority", ...]},
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
    |> Stat.get()
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

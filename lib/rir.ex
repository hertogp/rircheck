defmodule Rir do
  @moduledoc """
  Check your RIR registions.
  """

  alias Rir.Api
  alias Rir.Ctx

  @doc """
  Check an AS registration at [RIPEstat Data
  API](https://stat.ripe.net/docs/02.data-api/).

  Given `resource` is either
  - an IP address (will be translated to the ASN it belongs to)
  - an IP prefix (dito), or
  - an ASN number.

  """
  @spec check(binary) :: map
  def check(resource) do
    ctx = Ctx.new(resource)
    asn = ctx.asn

    Api.announced(ctx, asn)
    |> get_roas(asn)
    |> Api.consistency(asn)
    |> Api.whois(asn)
  rescue
    _ in RuntimeError -> raise ArgumentError, invalid_arg(resource)
  end

  @spec get_roas(map, binary) :: map
  defp get_roas(ctx, asn) do
    IO.inspect(ctx, label: :get_roas)

    Map.get(ctx.announced, asn, [])
    |> IO.inspect(label: :get_roas)
    |> Enum.reduce(ctx, fn pfx, acc -> Api.roa(acc, asn, pfx) end)
  end

  @spec invalid_arg(binary) :: binary
  defp invalid_arg(arg),
    do: "expected an IP address, prefix or AS number, got: #{inspect(arg)}"
end

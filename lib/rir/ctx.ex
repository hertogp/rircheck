defmodule Rir.Ctx do
  @moduledoc """
  Functions to create, read, update a context

  """

  alias Rir.Api

  # Helpers

  @spec to_asn(term) :: binary | RuntimeError
  defp to_asn(arg) do
    num = String.replace(arg, ~r/^AS/i, "")
    {_, ""} = Integer.parse(num)
    num
  rescue
    _ -> pfx2asn(arg)
  end

  defp pfx2asn(pfx) do
    ctx = Api.network(%{}, pfx)
    net = ctx.network[pfx]
    IO.inspect(net, label: :pfx2asn_net)

    case net[:error] do
      nil -> net.asn
      reason -> raise ArgumentError, "#{reason}"
    end
  end

  # API

  def new(arg, opts \\ []) do
    %{
      asn: to_asn(arg),
      opts: opts,
      error: nil
    }
  end

  @doc """
  Checks if given `asn` is announcing `prefix`.

  ## Example

      iex> %{
      ...>  announced: %{
      ...>    "123" => %{prefixes: ["1.1.1.0/24", "1.2.2.0/24"]}
      ...>  }
      ...> } |> announced?("123", "1.2.2.0/24")
      true

  """
  @spec announced?(map, binary, binary) :: boolean
  def announced?(ctx, asn, prefix) do
    prefix in ctx.announced[asn].prefixes
  rescue
    _ -> false
  end

  @doc """
  Checks wether there is a valid roa for given `asn` and `prefix`.

  """
  @spec roa_valid?(map, binary, binary) :: boolean
  def roa_valid?(ctx, asn, prefix) do
    roas = ctx.roa[{asn, prefix}]
    roas.status == :valid
  rescue
    _ -> false
  end

  def roa_valid(ctx, asn, prefix) do
    roas = ctx.roa[{asn, prefix}]
    Enum.find(roas.roas, fn {_, _, _, status} -> status == "valid" end)
  rescue
    _ -> nil
  end
end

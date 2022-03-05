defmodule Rir.Ctx do
  @moduledoc """
  Functions to create, read, update a context
  """

  alias Rir.Api

  def new(arg, opts \\ []) do
    %{
      asn: to_asn(arg),
      opts: opts,
      error: nil
    }
  end

  defp to_asn(arg) do
    num = String.replace(arg, ~r/^AS/i, "")
    {asn, ""} = Integer.parse(num)
    asn
  rescue
    _ -> pfx2asn(arg)
  end

  defp pfx2asn(pfx) do
    ctx = Api.network(%{}, pfx)
    net = ctx.network[pfx]

    case net[:error] do
      nil -> net.asn
      reason -> raise "#{reason}"
    end
  end
end

defmodule Rircheck do
  @moduledoc """
  Check your RIR registrations.

  The [RIPEstat Data API](https://stat.ripe.net/docs/02.data-api/)
  is the public data interface for RIPEstat. It is the
  only data source for the
  [RIPEstat widgets](https://stat.ripe.net/docs/widget_api)
  and the newer [RIPEstat UI](https://stat.ripe.net/app/launchpad).



  ## URL
  https://stat.ripe.net/data/<name>/data.json?param1=value1&param2=value2&...

  """

  def main(argv) do
    IO.puts("hello #{inspect(argv)}")

    argv
    |> parse_args()
    |> Rir.check()
    |> IO.inspect()
  end

  defp parse_args(argv) do
    hd(argv)
  end
end

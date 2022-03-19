defmodule Rircheck do
  @moduledoc """
  Check your RIR registration details for any ASN.

  The [RIPEstat Data API](https://stat.ripe.net/docs/02.data-api/)
  is the public data interface for RIPEstat. It is the
  only data source for the
  [RIPEstat widgets](https://stat.ripe.net/docs/widget_api)
  and the newer [RIPEstat UI](https://stat.ripe.net/app/launchpad).



  ## URL
  https://stat.ripe.net/data/<name>/data.json?param1=value1&param2=value2&...

  ## flags

  ```
  --timeout, timeout in milliseconds (default: 2000)
  --retries, number of retries in case of timeout errors

  ```

  Note:
  - each retry will double the timeout used

  ## Subcommands

  ### roa

  ```
  rircheck roa 3333
  rircheck roa 1.1.1.1  # IP gets mapped to its origin ASN
  ```

  Checks the roas status for all prefixes announced by given ASN.
  This also shows the first upstream neigboring ASN(s) for any prefix.

  ### 


  """

  def main(argv) do
    IO.puts("argv #{inspect(argv)}")

    argv
    |> parse_args()
    |> Rir.check()
    |> IO.inspect()
  end

  defp parse_args(argv) do
    hd(argv)
  end
end

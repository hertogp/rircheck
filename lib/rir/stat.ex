defmodule Rir.Stat do
  @moduledoc """
  Functions to call endpoints on the [RIPEstat Data
  API](https://stat.ripe.net/docs/02.data-api/).

  ## Them are the rules

  These are the rules for the usage of the data API:

  - no limit on the amount of requests
  - but please register if you plan to regularly do more than 1000 requests/day
  - see "Regular Usage" for details.
  - the system limits the usage to 8 concurrent requests coming from one IP address
  - RIPEstat [Service Terms and
    Conditions](https://www.ripe.net/about-us/legal/ripestat-service-terms-and-conditions)
    apply

  """

  alias HTTPoison

  @atoms %{
    "error" => :error,
    "info" => :info,
    "warning" => :warning,
    "ok" => :ok,
    "supported" => :supported,
    "deprecated" => :deprecated,
    "maintenance" => :maintenance,
    "development" => :development,
    "valid" => :valid,
    "invalid" => :invalid,
    "invalid_asn" => :invalid_asn,
    "unknown" => :unknown
  }

  HTTPoison.start()

  # API

  @doc """
  Returns the url for the given the api endpoint `name` & the `params` (keyword list).

  ## Example

      iex> url("announced-prefixes", resource: "1234")
      "https://stat.ripe.net/data/announced-prefixes/data.json?resource=1234"

  """
  @spec url(binary, Keyword.t()) :: binary
  def url(name, params \\ []) do
    params
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
    |> then(fn params -> "https://stat.ripe.net/data/#{name}/data.json?#{params}" end)
  end

  @doc """
  Returns a map with `call` details and either a `data` field or an `error` field.

  The resulting map is one of:
  - `%{call: call, data: data}`
  - `%{call: call, error: reason}`

  `call` is a map with call details:

  ```
  %{
    call: :supported | :deprecated | :development | :unknown
    http: integer, # the http status code
    info: nil | "some info msg"
    name: "api endpoint name",
    status: :ok | :error | :maintenance,
    url: "api-endpoint called",
    version: "major.minor"
  }

  ```

  The `call` meanings are:
  - `:supported`, endpoint is meant to be stable and without bugs
  - `:deprecated`, endpoint will cease to exist at some point in time
  - `:development`, endpoint is a WIP and might change or dissapear at any moment
  - `:unknown`, endpoint is unknown (a locally defined status)

  Strangely enough, when a non-existing endpoint is called, all `call` details
  indicate success and `data` is an empty map.  Only the `call.info` indicates
  that the data call does not exist.  Hence, `Rir.Stat.get/1` checks for
  this condition and if true:
  - sets `call` to `:unknown`
  - sets `status` to `:error`
  - removes the empty `data` map, and
  - adds an `error` field, saying "unknown API endpoint"

  `data` is a map whose contents depends on the api endpoint used.

  `error` appears when there is some type of error:
  - an parameter had an invalid value
  - the endpoint does not exist
  - the data could not be decoded
  - the server had some internal error
  - there were some network problems and no call was made

  In the latter case, `%{call: details, error: "some description"}` is
  returned, where the call details are limited to only these fields:
  - `info: "error reason: <reason>"`
  - `status: :error`
  - `url: endpoint that could not be reached`

  """
  @spec get(String.t(), Keyword.t()) :: map
  def get(url, opts \\ []) do
    # get an url response and decode its data part

    with {:ok, response} <- get_url(url, opts),
         {:ok, body} <- decode_json(response.body),
         {:ok, data} <- get_data(body),
         {:ok, status} <- get_status(body),
         {:ok, msgs} <- decode_messages(body) do
      case status do
        :error -> %{error: msgs[:error]}
        _ -> %{data: data}
      end
      |> Map.put(:call, %{
        call: to_atom(body["data_call_status"]),
        http: response.status_code,
        info: msgs[:info],
        name: body["data_call_name"],
        status: status,
        url: url,
        version: body["version"]
      })
      |> sanity_check()
    else
      {:error, reason} ->
        %{
          call: %{
            info: "error reason: #{reason}",
            status: :error,
            url: url
          },
          error: "GET: #{reason}"
        }
    end
  end

  # Helpers

  @spec get_url(binary, Keyword.t()) :: {:ok, HTTPoison.Response.t()} | {:error, any}
  defp get_url(url, opts) do
    case HTTPoison.get(url, opts) do
      {:ok, response} -> {:ok, response}
      {:error, error} -> {:error, error.reason}
    end
  end

  @spec decode_json(any) :: {:ok, term()} | {:eror, :json_decode}
  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, body} -> {:ok, body}
      _ -> {:error, :json_decode}
    end
  end

  @spec get_data(term()) :: {:ok, map} | {:error, :nodata}
  defp get_data(body) do
    case body["data"] do
      map when is_map(map) -> {:ok, map}
      _ -> {:error, :nodata}
    end
  end

  @spec decode_messages(term()) :: {:ok, map}
  defp decode_messages(body) do
    msgs =
      body["messages"]
      |> Enum.map(fn [type, msg] -> {to_atom(type), msg} end)
      |> Enum.into(%{})

    {:ok, msgs}
  rescue
    _ -> {:ok, %{}}
  end

  @doc """
  Returns an atom for a known first word in given `string`, otherwise just the
  first word.

  Note: the first word is also downcased.

  ## Examples

      iex> to_atom("deprecated - 2022-12-31")
      :deprecated

      iex> to_atom("But don't you worry")
      "but"

  """
  @spec to_atom(String.t()) :: atom | String.t()
  def to_atom(type) do
    type =
      type
      |> String.downcase()
      |> String.split()
      |> List.first()

    case @atoms[type] do
      nil -> type
      atom -> atom
    end
  end

  @spec get_status(term()) :: {:ok, atom | binary} | {:error, atom}
  defp get_status(body) do
    # ok, error or maintenance
    case body["status"] do
      nil -> {:error, :nostatus}
      status -> {:ok, to_atom(status)}
    end
  end

  @spec sanity_check(map) :: map
  defp sanity_check(%{call: call, data: data} = result) when map_size(data) == 0 do
    # correct the results when a non-existing API endpoint was called
    if String.match?(call.info, ~r/data\s*call\s*does\s*not\s*exist/i) do
      call =
        call
        |> Map.put(:call, :unknown)
        |> Map.put(:status, :error)

      %{call: call, error: "unknown API endpoint"}
    else
      result
    end
  end

  defp sanity_check(result),
    # ignore other conditions
    do: result
end

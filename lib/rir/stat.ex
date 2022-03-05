defmodule Rir.Stat do
  @moduledoc """
  Functions to retrieve data collections from the [RIPEstat Data
  API](https://stat.ripe.net/docs/02.data-api/).

  Functions return a map that is either
  - `%{error: code, reason: info}`, or
  - `%{status: code, type: type, data: map}

  ## Them are the rules

  These are the rules for the usage of the data API:

  - no limit on the amount of requests
  - but please register if you plan to regularly do more than 1000 requests/day
  - see "Regular Usage" for details.
  - the system limits the usage to 8 concurrent requests coming from one IP address
  - RIPEstat [Service Terms and
    Conditions](https://www.ripe.net/about-us/legal/ripestat-service-terms-and-conditions)
    apply

  ## Output data structure

  The resulting data has a key=>value structure. Each data call has its own
  output fields, which are detailed in the individual sections. The common
  fields that are provided by every call are:

  - `status`, string, indicates the status of the result of the data call.
        * `ok` for a successful query
        * `error` for unsuccessful query (see messages field)
        * `maintenance` in case the data call is undergoing maintenance.
  - `status_code`, integer, same as the HTTP status code.
  - `data_call_status`, string, indicates the status of the data call:
        * `supported`, this data call is meant to be stable and without bugs.
        * `deprecated` (usually provided with an expiration date)
        * `development` this data call is currently work in progress
  - `data_call_name`, string, holds the name of the data call
  - `version`, string, major.minor version of the response layout for this call
  - `cached`, boolean, True/False
  - `messages`, [["info"|"error", string]], human readable message
  - `process_time`, string, time it took to process the request (ms) or "not available"
  - `data`, the data itself.


  ## Data Overload Prevention

  This prevention mechanism should only kick in if the request stems from a
  browser (the referrer header set), but in case it happens for a non-browser
  request, it can easily suppressed by adding `data_overload_limit=ignore` parameter

  https://stat.ripe.net/data/<datacallname>/data.json?resource=AS3333&data_overload_limit=ignore

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

  def url(name, params \\ [])

  def url(name, :meta) do
    "https://stat.ripe.net/data/#{name}/meta/methodology"
  end

  def url(name, params) do
    params
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")
    |> then(fn params -> "https://stat.ripe.net/data/#{name}/data.json?#{params}" end)
  end

  @doc """
  Convert the result of an API call to a map.

  The resulting map is one of:
  - `%{call: details, data: decoded_json}`
  - `%{call: details, error: reason}`

  """
  @spec get(String.t()) :: map
  def get(url) do
    # get an url response and decode its data part

    with {:ok, response} <- get_url(url),
         {:ok, body} <- decode_json(response.body),
         {:ok, data} <- get_data(body),
         {:ok, status} <- get_status(body),
         {:ok, msgs} <- decode_messages(body) do
      case status do
        :error -> %{error: msgs[:error]}
        _ -> %{data: data}
      end
      |> Map.put(:call, %{
        url: url,
        status: status,
        name: body["data_call_name"],
        call: to_atom(body["data_call_status"]),
        version: body["version"],
        http: response.status_code,
        info: msgs[:info]
      })
    else
      {:error, reason} -> %{error: "GET: #{reason}", url: url}
    end
  end

  defp get_url(url) do
    case HTTPoison.get(url) do
      {:ok, response} -> {:ok, response}
      {:error, error} -> {:error, error.reason}
    end
  end

  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, body} -> {:ok, body}
      _ -> {:error, :json_decode}
    end
  end

  defp get_data(map) do
    case map["data"] do
      map when is_map(map) -> {:ok, map}
      _ -> {:error, :nodata}
    end
  end

  defp decode_messages(body) do
    msgs =
      body["messages"]
      |> Enum.map(fn [type, msg] -> {to_atom(type), msg} end)
      |> Enum.into(%{})

    {:ok, msgs}
  end

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

  @spec get_status(map) :: {:ok, atom | binary} | {:error, atom}
  defp get_status(map) do
    # ok, error, maintenance
    case map["status"] do
      nil -> {:error, :nostatus}
      status -> {:ok, to_atom(status)}
    end
  end
end

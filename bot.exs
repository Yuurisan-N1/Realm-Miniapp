Code.require_file("utils/json.ex", __DIR__)
Code.require_file("utils/banner.ex", __DIR__)

defmodule MinerXRealm do
  @moduledoc false

  @my_project "MinerX Realm Miniapp"
  @base_url "https://minerxrealm.zekobusiness0.workers.dev"
  @root __DIR__
  @unit "Coins"
  @fallback_cycle 3600

  @reset "\e[0m"
  @bold "\e[1m"
  @red "\e[91m"
  @green "\e[92m"
  @yellow "\e[93m"

  def run do
    :logger.set_primary_config(:level, :error)
    install_signal_handler()

    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    Banner.set_title(@my_project)
    Banner.show_banner(@my_project)

    accounts = load_lines("data.txt")

    if accounts == [] do
      red("File data.txt is empty, please add your initData entries")
      System.halt(1)
    end

    proxies = load_lines("proxy.txt")
    settings = load_settings()

    loop(accounts, proxies, settings, 1)
  end

  defp loop(accounts, proxies, settings, cycle) do
    yellow("Starting automation cycle number #{cycle}")

    Enum.with_index(accounts)
    |> Enum.each(fn {account, index} ->
      if index > 0, do: IO.puts("")

      proxy = proxy_for(proxies, index)

      case proxy do
        nil -> yellow("Running without proxy for this account.")
        line -> yellow("Using proxy #{mask_proxy(line)}")
      end

      try do
        process_account(account, index, proxy, settings)
      rescue
        _error -> red("Account #{index + 1} was skipped after an error")
      end
    end)

    yellow("All accounts processed for cycle number #{cycle}")

    countdown(sleep_seconds(settings), "Next cycle starts in")
    Banner.show_banner(@my_project)
    loop(accounts, proxies, settings, cycle + 1)
  end

  defp process_account(account, index, proxy, settings) do
    label = "#{index + 1}"

    case identity(account) do
      {:ok, username, first_name} ->
        case fetch_user(account, proxy) do
          {:ok, data} ->
            user = get(data, "user", %{})

            cond do
              get(data, "banned", false) ->
                red("Account #{label} is banned and was skipped by the bot")

              not is_map(user) or map_size(user) == 0 ->
                red("Account #{label} state fetch failed with an empty snapshot")

              true ->
                name = display_name(user, first_name)

                green("Signed in #{shorten(clean_text(name, "account"), "account", 20)} with #{money(get(user, "coins", 0))} #{@unit}")

                process_mining(user, account, proxy)
                process_daily(account, proxy)
                process_tasks(account, proxy, settings)
                process_checkin(account, proxy)
                process_leaderboard(username, account, proxy)
                process_friends(account, proxy)
                :ok
            end

          {:error, reason} ->
            red("Account #{label} state fetch failed with #{short_reason(reason)}")
        end

      {:error, reason} ->
        red("Account #{label} initData refused with #{short_reason(reason)}")
    end
  end

  defp process_mining(user, account, proxy) do
    started = get(user, "mining_started_at")
    duration = whole(get(user, "mining_cycle_duration_seconds", @fallback_cycle), @fallback_cycle)
    left = remaining(started, duration)

    cond do
      is_nil(started) or started == "" ->
        start_mining(account, proxy)

      left > 0 ->
        yellow("Mining is still running with #{format_duration(left)} left")

      true ->
        claim_mining(account, whole(get(user, "coins", 0), 0), proxy)
    end
  end

  defp start_mining(account, proxy) do
    case call("/api/mine/start", %{}, account, proxy) do
      {:ok, _data} ->
        green("Mining session started and the cycle is now running")

      {:error, reason} ->
        text = String.upcase(to_string(reason))

        if String.contains?(text, "WALLET") do
          yellow("Mining is skipped because no wallet is linked yet")
        else
          yellow("Mining session start was refused with #{short_reason(reason)}")
        end
    end
  end

  defp claim_mining(account, before, proxy) do
    case call("/api/mine/claim", %{}, account, proxy) do
      {:ok, _data} ->
        case fetch_user(account, proxy) do
          {:ok, data} ->
            gained = whole(get(get(data, "user", %{}), "coins", 0), 0) - before

            if gained > 0 do
              green("Mining reward of #{money(gained)} #{@unit} was claimed")
            else
              yellow("Mining claim was refused by the server on this run")
            end

          {:error, _reason} ->
            yellow("Mining claim was refused by the server on this run")
        end

      {:error, reason} ->
        text = String.upcase(to_string(reason))

        if String.contains?(text, "NOT_FINISHED") do
          case fetch_user(account, proxy) do
            {:ok, data} ->
              user = get(data, "user", %{})

              left =
                remaining(
                  get(user, "mining_started_at"),
                  whole(get(user, "mining_cycle_duration_seconds", @fallback_cycle), @fallback_cycle)
                )

              yellow("Mining is still running with #{format_duration(left)} left")

            {:error, _reason} ->
              yellow("Mining claim is still cooling down on the server")
          end
        else
          yellow("Mining claim was refused by the server on this run")
        end
    end
  end

  defp process_daily(account, proxy) do
    credited =
      [
        {"streak", "/api/streak/claim", "Daily streak"},
        {"spin", "/api/spin/claim", "Daily spin"},
        {"chest", "/api/chest/claim", "Daily chest"},
        {"gift", "/api/giftpick/claim", "Daily gift"}
      ]
      |> Enum.map(fn {kind, path, label} -> claim_daily(kind, path, label, account, proxy) end)
      |> Enum.filter(&is_integer/1)

    case credited do
      [] -> green("Every daily reward was already claimed for this account")
      _ -> :ok
    end
  end

  defp claim_daily(kind, path, label, account, proxy) do
    case call(path, %{}, account, proxy) do
      {:ok, data} ->
        case daily_amount(kind, data) do
          amount when amount > 0 ->
            case kind do
              "streak" ->
                green(
                  "Daily streak credited #{money(amount)} #{@unit} on day #{whole(get(data, "day_claimed", 1), 1)}"
                )

              _ ->
                green("#{label} credited #{money(amount)} #{@unit}")
            end

            amount

          _ ->
            nil
        end

      {:error, reason} ->
        text = String.upcase(to_string(reason))

        cond do
          String.contains?(text, "ALREADY") or String.contains?(text, "SPUN") ->
            nil

          String.contains?(text, "NOT_READY") or String.contains?(text, "NOT_DUE") ->
            nil

          true ->
            yellow("#{label} was refused with #{short_reason(reason)}")
            nil
        end
    end
  end

  defp daily_amount("streak", data), do: whole(get(data, "reward", 0), 0)
  defp daily_amount(_kind, data), do: whole(get(data, "prize_amount", 0), 0)

  defp process_tasks(account, proxy, settings) do
    case call("/api/tasks/list", %{}, account, proxy) do
      {:ok, data} ->
        tasks =
          case get(data, "tasks", []) do
            list when is_list(list) -> list
            _ -> []
          end

        open =
          if membership_tasks_enabled(settings) do
            tasks
          else
            Enum.reject(tasks, &(not membership_task?(&1)))
          end

        dropped = length(tasks) - length(open)

        cond do
          open == [] and dropped > 0 ->
            :ok

          open == [] ->
            green("Every available account task was already completed")

          true ->
            green("Found #{plural(length(open), "task")} to process")

            Enum.each(open, fn task -> claim_task(task, account, proxy) end)
        end

      {:error, reason} ->
        red("Task list could not be fetched with #{short_reason(reason)}")
    end
  end

  defp membership_task?(task) do
    case get(task, "requires_membership", false) do
      true -> true
      "true" -> true
      _ -> false
    end
  end

  defp membership_tasks_enabled(settings) do
    case get(get(settings, "settings", %{}), "requires_membership", true) do
      true -> true
      false -> false
      value when is_number(value) -> value != 0
      value when is_binary(value) -> String.downcase(value) in ["true", "yes", "on", "1"]
      _ -> true
    end
  end

  defp claim_task(task, account, proxy) do
    title = shorten(clean_text(get(task, "title", "task"), "task"), "task", 18)

    case call("/api/tasks/claim", %{"task_id" => get(task, "id")}, account, proxy) do
      {:ok, data} ->
        green(
          "Task #{title} claimed successfully earning #{money(whole(get(data, "reward", 0), 0))} #{@unit}"
        )

      {:error, reason} ->
        text = String.upcase(to_string(reason))

        cond do
          String.contains?(text, "NOT_MEMBER") or String.contains?(text, "NOT_JOINED") ->
            yellow("Task #{title} still needs a manual channel join")

          String.contains?(text, "ALREADY_CLAIMED") ->
            yellow("Task #{title} was already completed on this account")

          String.contains?(text, "TASK_FULL") ->
            yellow("Task #{title} is no longer available")

          true ->
            yellow("Task #{title} was refused with #{short_reason(reason)}")
        end
    end
  end

  defp process_checkin(account, proxy) do
    results =
      [1, 2, 3, 4, 5]
      |> Enum.map(fn task -> claim_checkin(task, account, proxy) end)

    case Enum.filter(results, &is_integer/1) do
      [] ->
        if Enum.any?(results, &(&1 == :refused)) do
          yellow("Daily check in was refused by the server with not_verified")
        else
          green("Every daily reward was already claimed for this account")
        end

      _ ->
        :ok
    end
  end

  defp claim_checkin(task, account, proxy) do
    case call("/api/checkin/claim", %{"task" => task}, account, proxy) do
      {:ok, data} ->
        amount = whole(get(data, "reward", 0), 0)

        if amount > 0 do
          green("Daily check in credited #{money(amount)} #{@unit} on task #{task}")
          amount
        else
          nil
        end

      {:error, reason} ->
        text = String.upcase(to_string(reason))

        cond do
          String.contains?(text, "NOT_VERIFIED") or String.contains?(text, "NOT_MEMBER") -> :refused
          String.contains?(text, "ALREADY") -> nil
          true -> :refused
        end
    end
  end

  defp process_leaderboard(username, account, proxy) do
    case call("/api/leaderboard", %{}, account, proxy) do
      {:ok, data} ->
        rows = get(data, "ads", [])

        case rank_of(rows, username) do
          {rank, _name} ->
            green("Leaderboard position #{rank} of #{length(rows)} miners")

          nil ->
            yellow("This account is not ranked on the leaderboard yet")
        end

      {:error, _reason} ->
        yellow("The leaderboard position was not returned by the server")
    end
  end

  defp rank_of(rows, username) when is_list(rows) and is_binary(username) do
    if username == "" do
      nil
    else
      wanted = String.downcase(username)

      rows
      |> Enum.find(fn row -> String.downcase(to_string(get(row, "name", ""))) == wanted end)
      |> case do
        nil -> nil
        row -> {whole(get(row, "rank", 0), 0), get(row, "name", "")}
      end
    end
  end

  defp rank_of(_rows, _username), do: nil

  defp process_friends(account, proxy) do
    case call("/api/friends/claim_earnings", %{}, account, proxy) do
      {:ok, data} ->
        credited = whole(get(data, "claimed", get(data, "amount", 0)), 0)

        if credited > 0 do
          green("Referral bonus credited #{money(credited)} #{@unit}")
        else
          yellow("No referral commission was pending on this account")
        end

      {:error, reason} ->
        text = String.upcase(to_string(reason))

        if String.contains?(text, "BELOW_MINIMUM") do
          yellow("No referral commission was pending on this account")
        else
          yellow("Referral bonus could not be claimed on this run")
        end
    end
  end

  defp fetch_user(account, proxy) do
    call("/api/user", %{}, account, proxy)
  end

  defp identity(init_data) do
    with {:ok, params} <- parse_query(init_data),
         raw when is_binary(raw) <- Map.get(params, "user"),
         {:ok, user} <- YuurisanJSON.decode(URI.decode_www_form(raw)),
         id when not is_nil(id) <- get(user, "id") do
      {:ok, to_string(get(user, "username", "")), to_string(get(user, "first_name", ""))}
    else
      nil -> {:error, "user object missing"}
      {:error, reason} -> {:error, reason}
      _ -> {:error, "unreadable initData"}
    end
  end

  defp parse_query(raw) do
    pairs =
      raw
      |> String.trim()
      |> String.split("&")
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn pair ->
        case String.split(pair, "=", parts: 2) do
          [key, value] -> {key, value}
          [key] -> {key, ""}
        end
      end)

    if Enum.any?(pairs, fn {key, _value} -> key == "hash" end) do
      {:ok, Map.new(pairs)}
    else
      {:error, "initData has no hash"}
    end
  end

  defp call(path, payload, account, proxy) do
    case request(path, payload, account, proxy) do
      {:ok, body} -> unwrap(body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp unwrap(body) do
    case body do
      %{"error" => error} -> {:error, error}
      %{} = data -> {:ok, data}
      _ -> {:ok, %{}}
    end
  end

  defp request(path, payload, init_data, proxy) do
    url = String.to_charlist(String.trim_trailing(@base_url, "/") <> path)
    {profile, auth} = proxy_setup(proxy)

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"accept", ~c"*/*"},
      {~c"origin", String.to_charlist(@base_url)},
      {~c"referer", String.to_charlist(@base_url <> "/")},
      {~c"user-agent",
       ~c"Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"}
    ]

    body =
      payload
      |> Map.put("initData", init_data)
      |> YuurisanJSON.encode()

    options = [ssl: [verify: :verify_none], timeout: 30_000, connect_timeout: 15_000] ++ auth

    case :httpc.request(:post, {url, headers, ~c"application/json", body}, options, [body_format: :binary], profile) do
      {:ok, {{_version, status, _reason}, _headers, response}} when status >= 200 and status < 300 ->
        case YuurisanJSON.decode(response) do
          {:ok, value} -> {:ok, value}
          {:error, _} -> {:error, "unreadable response"}
        end

      {:ok, {{_version, status, _reason}, _headers, response}} ->
        case YuurisanJSON.decode(response) do
          {:ok, %{"error" => error}} -> {:error, error}
          {:ok, %{"message" => message}} -> {:error, message}
          {:ok, _} -> {:error, "HTTP #{status}"}
          {:error, _} -> {:error, "HTTP #{status}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp proxy_setup(nil), do: {:default, []}

  defp proxy_setup(line) do
    case parse_proxy(line) do
      {host, port, user, pass} -> proxy_profile(host, port, user, pass)
      {host, port} -> proxy_profile(host, port, "", "")
      nil -> {:default, []}
    end
  end

  defp proxy_profile(host, port, user, pass) do
    name = String.to_atom("proxy_#{host}_#{port}")
    address = {String.to_charlist(host), port}

    case :inets.start(:httpc, profile: name) do
      {:ok, _pid} -> :httpc.set_options([proxy: {address, []}, https_proxy: {address, []}], name)
      {:error, {:already_started, _pid}} -> :ok
      _other -> :ok
    end

    case user do
      "" -> {name, []}
      _ -> {name, [proxy_auth: {String.to_charlist(user), String.to_charlist(pass)}]}
    end
  end

  defp parse_proxy(line) do
    value =
      line
      |> String.trim()
      |> String.replace_prefix("http://", "")
      |> String.replace_prefix("https://", "")
      |> String.replace_prefix("socks5://", "")

    case String.split(value, "@") do
      [credentials, host_part] ->
        case String.split(credentials, ":") do
          [user, pass] -> with_host_port(host_part, user, pass)
          _other -> with_host_port(host_part, "", "")
        end

      [host_part] ->
        case String.split(host_part, ":") do
          [host, port] -> with_port(host, port)
          [host, port, user, pass] -> with_port_creds(host, port, user, pass)
          _other -> nil
        end
    end
  end

  defp with_host_port(host_part, user, pass) do
    case String.split(host_part, ":") do
      [host, port] -> with_port_creds(host, port, user, pass)
      _other -> nil
    end
  end

  defp with_port(host, port) do
    case Integer.parse(port) do
      {number, ""} -> {host, number}
      _other -> nil
    end
  end

  defp with_port_creds(host, port, user, pass) do
    case Integer.parse(port) do
      {number, ""} -> {host, number, user, pass}
      _other -> nil
    end
  end

  defp mask_proxy(line) do
    case parse_proxy(line) do
      {host, port, _user, _pass} -> "http://user:pass@#{mask_host(host)}:#{port}"
      {host, port} -> "http://user:pass@#{mask_host(host)}:#{port}"
      nil -> "http://user:pass@***:***"
    end
  end

  defp mask_host(host) do
    parts = String.split(host, ".")

    case parts do
      [a, _b, _c, d] ->
        "#{a}*****#{d}"

      _other ->
        if String.length(host) > 4 do
          String.slice(host, 0, 2) <> "*****" <> String.slice(host, -2, 2)
        else
          "***"
        end
    end
  end

  defp proxy_for([], _index), do: nil
  defp proxy_for(proxies, index), do: Enum.at(proxies, rem(index, length(proxies)))

  defp load_lines(name) do
    case File.read(Path.join(@root, name)) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _reason} ->
        []
    end
  end

  defp load_settings do
    case File.read(Path.join(@root, "config.json")) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, value} -> value
          {:error, _reason} -> default_settings()
        end

      {:error, _reason} ->
        settings = default_settings()
        File.write(Path.join(@root, "config.json"), YuurisanJSON.encode_pretty(settings))
        settings
    end
  end

  defp default_settings, do: %{"settings" => %{"sleep_seconds" => 3600, "requires_membership" => true}}

  defp sleep_seconds(settings) do
    case get(get(settings, "settings", %{}), "sleep_seconds", 3600) do
      value when is_integer(value) and value > 0 -> value
      value when is_float(value) and value > 0 -> trunc(value)
      _other -> 3600
    end
  end

  defp get(map, key, default \\ nil)
  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp get(_other, _key, default), do: default

  defp display_name(user, first_name) do
    value = get(user, "display_name", "")

    cond do
      is_binary(value) and String.trim(value) != "" -> value
      is_binary(first_name) and String.trim(first_name) != "" -> first_name
      true -> "account"
    end
  end

  defp clean_text(value, fallback) do
    text =
      value
      |> stringify()
      |> String.replace(
        ["[", "]", "|", "#", "!", "@", "$", "%", "^", "&", "*", "(", ")", "-"],
        " "
      )

    case String.split(text) |> Enum.join(" ") do
      "" -> fallback
      cleaned -> cleaned
    end
  end

  defp short_reason(reason), do: shorten(clean_text(reason, "reason"), "reason", 20)

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp stringify({:failed_connect, _reason}), do: "no network connection"
  defp stringify({:timeout, _reason}), do: "the request timed out"
  defp stringify({:failed_connect, _reason, _host}), do: "no network connection"
  defp stringify(value), do: inspect(value)

  defp whole(value, _fallback) when is_integer(value), do: value
  defp whole(value, _fallback) when is_float(value), do: trunc(value)
  defp whole(_value, fallback), do: fallback

  defp money(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 2)
  end

  defp money(value), do: to_string(value)

  defp remaining(nil, _duration), do: 0

  defp remaining(started, duration) do
    case parse_iso(started) do
      nil -> 0
      seconds -> max(duration - (now_seconds() - seconds), 0)
    end
  end

  defp parse_iso(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.to_unix(datetime)
      _other -> nil
    end
  end

  defp parse_iso(_value), do: nil

  defp now_seconds, do: System.system_time(:second)

  defp install_signal_handler do
    handler = fn ->
      IO.write("\n" <> @red <> @bold <> "Script stopped by user" <> @reset <> "\n")
      System.halt(0)
    end

    for signal <- [:sigint, :sigterm, :sighup, :sigquit] do
      try do
        System.trap_signal(signal, handler)
      rescue
        _error -> :ok
      end
    end
  end

  defp shorten(value, fallback, limit) do
    text = to_string(value)

    case String.slice(text, 0, limit) do
      "" -> fallback
      short -> short
    end
  end

  defp plural(count, word) do
    if count == 1, do: "#{count} #{word}", else: "#{count} #{pluralize(word)}"
  end

  defp pluralize(word) do
    cond do
      String.ends_with?(word, "y") -> String.slice(word, 0, String.length(word) - 1) <> "ies"
      true -> word <> "s"
    end
  end

  defp countdown(seconds, label) do
    left = max(trunc(seconds), 0)

    if left >= 1 do
      width = frame(label, left, 0)
      tick(left, label, width)
    end
  end

  defp tick(0, _label, width) do
    IO.write("\r" <> String.duplicate(" ", width) <> "\r")
  end

  defp tick(left, label, width) do
    width = frame(label, left, width)
    :timer.sleep(1000)
    tick(left - 1, label, width)
  end

  defp frame(label, left, width) do
    text = label <> " " <> format_duration(left)
    IO.write("\r" <> @yellow <> @bold <> text <> @reset)
    max(width, String.length(text))
  end

  defp format_duration(total) do
    days = div(total, 86_400)
    hours = div(rem(total, 86_400), 3600)
    minutes = div(rem(total, 3600), 60)
    seconds = rem(total, 60)

    if days > 0 do
      pad(days) <> ":" <> pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    else
      pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    end
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")

  defp green(message), do: IO.puts(@green <> @bold <> message <> @reset)
  defp yellow(message), do: IO.puts(@yellow <> @bold <> message <> @reset)
  defp red(message), do: IO.puts(@red <> @bold <> message <> @reset)
end

MinerXRealm.run()

defmodule Reaxive do
  use Application.Behaviour

  # See http://elixir-lang.org/docs/stable/Application.Behaviour.html
  # for more information on OTP Applications
  def start(_type, _args) do
    Reaxive.Supervisor.start_link
  end

  @type signal :: {:Signal, reference, pid, any}
  @type signal(a) :: {:Signal, reference, pid, a}

  defrecord Signal, 
  	id: nil, # id of the invividual sigal
  	source: nil, # pid of the source 
  	value: nil # current value of the signal

  @doc """
  Implements the internal receive loop for a signal. 

  Its task is to manage the subscriptions of signals to which values are propagated. 
  Subscriptions are managed with `register`, `unregister` and `DOWN` messages. The 
  latter are created by monitoring signals and ensures that died signals are automatically
  unsubscribed, helping in both situations when nasty things happen and when signals do
  not know how to unsubscribe. 
  """
  @spec signal_handler([{signal(a), reference}], ((a) -> b), signal(b)) :: no_return when a: var, b: var
  def signal_handler(fun, signal), do: signal_handler([], fun, signal)
  def signal_handler(subscriptions, fun, signal) do
    receive do
      {:register, s = Signal[]} ->
        log("register signal #{inspect s}")
        m = Process.monitor(s.source)
        signal_handler([{s, m} | subscriptions], fun, signal)
      {:unregister, s = Signal[]} ->
        log("unregister signal #{inspect s}")
        signal_handler(subscriptions |> 
          Enum.reject(fn({sub, _mon}) -> sub.source == s.source end), fun, signal)
      {:DOWN, _m, :process, pid, reason} ->
        # a monitored Signal died, so take it out of the subscriptions
        log("got DOWN for process #{inspect pid} and reason #{inspect reason}")
        signal_handler(subscriptions |> 
          Enum.reject(fn({sub, _mon}) -> sub.source == pid end), fun, signal)
      msg = Signal[]-> 
        log("got signal #{inspect msg}, calculating fun with value #{inspect msg.value}")
        v = fun . (msg.value)
        s = signal.update(id: :erlang.make_ref(), value: v)
        subscriptions |> Enum.each fn({sub, _m}) -> send(sub.source, s) end
        signal_handler(subscriptions, fun, signal)
      any -> 
        log("got weird message #{inspect any}")
        Signal[] = any
      end
  end
  

  @doc """
  Function `every` is an input signal, i.e. it generates new signal values
  in an asynchronous manner. As an input signal is does not rely an any other
  signals, it is a root in dependency graph of signals.
  """
  @spec every(integer) :: signal(integer)
  def every(millis) do
    my_signal = make_signal()
    p = spawn(fn() -> 
      :timer.send_interval(millis, my_signal.update(value: :go))
      fun = fn(_v) -> :os.timestamp() end
      signal_handler(fun, my_signal.update(source: self))
    end)
    my_signal.update(source: p)
  end

  @doc """
  Function `lift` creates a new signal of type `b` by applying
  function `fun` to each value of `signal`, which has type `a`. 
  Consequently, function `fun` maps from type `a` to `b`.
  """
  @spec lift((a -> b), signal(a)) :: signal(b) when a: var, b: var 
  def lift(fun, signal = Signal[]) do
    my_signal = make_signal()
  	p = spawn(fn() -> 
      s = my_signal.update(source: self)
      send(signal.source, {:register, s})
      signal_handler(fun, s)
    end)
    my_signal.update(source: p)
  end
  
  @doc """
  Renders a signal as text. 
  """
  @spec as_text(signal|pid) :: :none # when a: var
  def as_text(s) when is_pid(s) do
    signal = make_signal
    as_text(signal.update(source: s))
  end
  def as_text(signal = Signal[]) do
    fun = fn(value) -> IO.inspect(value) end
    my_signal = make_signal()
    p = spawn(fn() -> 
      s = my_signal.update(source: self)
      send(signal.source, {:register, s})
      signal_handler(fun, s)
    end)
    my_signal.update(source: p)
  end


  @doc """
  Converts a signal in to regular lazy Elixir stream.
  """
  @spec as_stream(signal, pos_integer | :infinity) :: Enumerable.t
  def as_stream(signal = Signal[], timeout \\ :infinity) do
    # Register a signal process, which also reacts
    # on a `{:get, make_ref()}` message and answers with a 
    # `{:got, ref, value}`message. 
    # this signal process can have its own loop function
    #
    my_signal = make_signal()
    p = spawn(fn() -> 
      s = my_signal.update(source: self)
      send(signal.source, {:register, s})
      # TODO proper stream-handler
      stream_handler(s)
    end)
    sig = my_signal.update(source: p)
    next_fun = fn(_acc) ->
      ref = make_ref()
      send(sig.source, {:get, ref, self})
      receive do
        {:got, ^ref, value} -> {value, :next}
        after timeout -> nil
      end
    end
    Stream.resource(
      fn() ->next_fun . (:next) |> elem(0) end, # lazy first value
      next_fun, # all other values
      fn(_) -> stop(sig) end # after termination
      )
  end
  
  def from_stream(s) do
    
  end
  
  def stream_handler(signal = Signal[]) do
    receive do
      {:get, ref, pid} when is_reference(ref) and is_pid(pid) ->
        receive do 
          s = Signal[] -> send(pid, {:got, ref, s.value})
        end
    end
    stream_handler(signal)
  end
  
  
  @doc """
  Creates a new signal instance with optional `value`.
  """
  @spec make_signal(a) :: signal(a) when a: var
  def make_signal(value \\ nil) do
    Signal.new(id: :erlang.make_ref(), source: self, value: value)
  end

  def log(msg) do
    IO.puts("#{inspect self}: #{inspect msg}")
  end  

  def stop(signal = Signal[]) do
    Process.exit(signal.source, :normal)
  end

  def test do
    m = every 1_000
    c = lift(fn(_) -> :toc end, m)
    as_text(c)
  end
  
  def test2 do
    m = every 1_000
    c = lift(fn(_) -> :toc end, m)
    s = as_stream(c)
    Stream.take(s, 5) |> Stream.with_index |> Enum.to_list
  end

end
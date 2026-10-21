module Imports
  # Raised when a pipeline step re-reads its import run under a row lock
  # and finds a status that no longer allows it -- typically because a
  # concurrent request (a double click, a parallel API call) already moved
  # the run on. A refusal, not a crash: the run is left exactly as it was.
  class StaleStateError < StandardError; end
end

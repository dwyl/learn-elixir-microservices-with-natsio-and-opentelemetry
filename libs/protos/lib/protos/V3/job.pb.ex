defmodule Mcsv.V3.EnqueueJobRequest.ArgsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Mcsv.V3.EnqueueJobRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof :schedule, 0

  field :worker, 1, type: :string
  field :queue, 2, type: :string
  field :args, 3, repeated: true, type: Mcsv.V3.EnqueueJobRequest.ArgsEntry, map: true
  field :priority, 4, type: :int32
  field :max_attempts, 5, type: :int32, json_name: "maxAttempts"
  field :scheduled_at, 6, type: :int64, json_name: "scheduledAt", oneof: 0
  field :schedule_in, 7, type: :int32, json_name: "scheduleIn", oneof: 0
end

defmodule Mcsv.V3.EnqueueJobResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job_id, 1, type: :int64, json_name: "jobId"
  field :state, 2, type: :string
  field :scheduled_at, 3, type: :int64, json_name: "scheduledAt"
  field :success, 4, type: :bool
  field :error, 5, type: :string
end

defmodule Mcsv.V3.GetJobStatusRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job_id, 1, type: :int64, json_name: "jobId"
end

defmodule Mcsv.V3.JobStatusResponse.ArgsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Mcsv.V3.JobStatusResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job_id, 1, type: :int64, json_name: "jobId"
  field :worker, 2, type: :string
  field :queue, 3, type: :string
  field :state, 4, type: :string
  field :args, 5, repeated: true, type: Mcsv.V3.JobStatusResponse.ArgsEntry, map: true
  field :attempt, 6, type: :int32
  field :max_attempts, 7, type: :int32, json_name: "maxAttempts"
  field :attempted_at, 8, type: :int64, json_name: "attemptedAt"
  field :attempted_by, 9, type: :string, json_name: "attemptedBy"
  field :errors, 10, repeated: true, type: :string
  field :inserted_at, 11, type: :int64, json_name: "insertedAt"
  field :scheduled_at, 12, type: :int64, json_name: "scheduledAt"
  field :completed_at, 13, type: :int64, json_name: "completedAt"
end

defmodule Mcsv.V3.ListJobsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :queue, 1, type: :string
  field :state, 2, type: :string
  field :worker, 3, type: :string
  field :limit, 4, type: :int32
end

defmodule Mcsv.V3.CancelJobRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job_id, 1, type: :int64, json_name: "jobId"
end

defmodule Mcsv.V3.CancelJobResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
end

defmodule Mcsv.V3.RetryJobRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job_id, 1, type: :int64, json_name: "jobId"
end

defmodule Mcsv.V3.RetryJobResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
  field :scheduled_at, 3, type: :int64, json_name: "scheduledAt"
end

defmodule Mcsv.V3.GetQueueStatsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :queue, 1, type: :string
end

defmodule Mcsv.V3.GetQueueStatsResponse.QueueStats do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :queue, 1, type: :string
  field :available, 2, type: :int32
  field :scheduled, 3, type: :int32
  field :executing, 4, type: :int32
  field :retryable, 5, type: :int32
  field :completed, 6, type: :int32
  field :discarded, 7, type: :int32
end

defmodule Mcsv.V3.GetQueueStatsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :stats, 1, repeated: true, type: Mcsv.V3.GetQueueStatsResponse.QueueStats
end

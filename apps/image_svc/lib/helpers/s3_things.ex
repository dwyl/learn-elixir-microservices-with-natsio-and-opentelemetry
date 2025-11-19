defmodule S3Things do
  @moduledoc """
  Hlelpers for S3 interactions (MinIO, AWS S3, etc.)
  """

  require Logger

  def s3_opts do
    s3_config = Application.get_env(:image_svc, :s3, [])

    [
      object_storage_endpoint:
        Keyword.get(s3_config, :object_storage_endpoint, "http://localhost:9000"),
      access_key_id: Keyword.get(s3_config, :access_key_id, "minioadmin"),
      secret_access_key: Keyword.get(s3_config, :secret_access_key, "minioadmin"),
      region: Keyword.get(s3_config, :region, "us-east-1"),
      expiry_bucket_retention: Keyword.get(s3_config, :expiry_bucket_retention, 3600)
    ]
  end

  def generate_s3_url(bucket, key) do
    ReqS3Storage.generate_presigned_url(bucket, key, s3_opts())
  end

  def bucket_image do
    s3_config = Application.get_env(:image_svc, :s3, [])
    Keyword.get(s3_config, :image_bucket, "msvc-images")
  end

  def build_s3_req(opts) do
    Req.new()
    |> ReqS3.attach(
      aws_endpoint_url_s3: Keyword.fetch!(opts, :object_storage_endpoint),
      aws_sigv4: [
        access_key_id: Keyword.fetch!(opts, :access_key_id),
        secret_access_key: Keyword.fetch!(opts, :secret_access_key),
        region: Keyword.get(opts, :region, "us-east-1")
      ]
    )
  end

  def upload_binary_to_s3(binary, bucket, job_id) do
    case ReqS3Storage.store(binary, bucket, job_id, "application/pdf", s3_opts()) do
      {:ok, %{bucket: bucket, key: key, size: size, presigned_url: _presigned_url}} ->
        Logger.info("[PullConsumer] Uploaded PDF to #{bucket}/#{key} (#{size} bytes)")
        # Return tuple matching expected format
        {:ok, {bucket, key, size}}

      {:error, reason} ->
        Logger.error("[PullConsumer] Failed to upload PDF: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

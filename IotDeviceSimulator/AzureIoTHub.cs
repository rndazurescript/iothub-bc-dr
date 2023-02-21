
using Azure.Messaging.EventHubs.Consumer;
using Microsoft.Azure.Devices;
using Microsoft.Azure.Devices.Client;
using Microsoft.Azure.Devices.Common.Exceptions;
using System;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

    public static class AzureIoTHub
    {
        /// <summary>
        /// Please replace with correct connection string value
        /// The connection string could be got from Azure IoT Hub -> Shared access policies -> iothubowner -> Connection String:
        /// </summary>
        private static string iotHubConnectionString = Environment.GetEnvironmentVariable("IOT_HUB_CONNSTR");

        /// <summary>
        /// Please replace with correct device connection string
        /// The device connect string could be got from Azure IoT Hub -> Devices -> {your device name } -> Connection string
        /// </summary>
        private static string deviceConnectionString = Environment.GetEnvironmentVariable("DEVICE_CONNSTR");

        public static async Task<string> CreateDeviceIdentityAsync(string deviceName)
        {
            var registryManager = RegistryManager.CreateFromConnectionString(iotHubConnectionString);
            var device = new Device(deviceName);
            try
            {
                device = await registryManager.AddDeviceAsync(device);
            }
            catch (DeviceAlreadyExistsException)
            {
                device = await registryManager.GetDeviceAsync(deviceName);
            }

            return device.Authentication.SymmetricKey.PrimaryKey;
        }

        public static async Task SendDeviceToCloudMessageAsync(CancellationToken cancelToken)
        {
            var deviceClient = DeviceClient.CreateFromConnectionString(deviceConnectionString);

            double avgTemperature = 70.0D;
            var rand = new Random();

            while (!cancelToken.IsCancellationRequested)
            {
                try{
                    double currentTemperature = avgTemperature + rand.NextDouble() * 4 - 3;

                    var telemetryDataPoint = new
                    {
                        Temperature = currentTemperature
                    };
                    var messageString = JsonSerializer.Serialize(telemetryDataPoint);
                    var message = new Microsoft.Azure.Devices.Client.Message(Encoding.UTF8.GetBytes(messageString))
                    {
                        ContentType = "application/json",
                        ContentEncoding = "utf-8"
                    };
                    await deviceClient.SendEventAsync(message);
                    Console.WriteLine($"{DateTime.Now} > Sending message: {messageString}");

                    await Task.Delay(5000);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"{DateTime.Now} > Error sending message: {ex.GetType().ToString()}::{ex.Message}. Retrying after 5 seconds...");
                    Task.Delay(5000);
                }
            }
        }

        public static async Task<string> ReceiveCloudToDeviceMessageAsync()
        {
            var oneSecond = TimeSpan.FromSeconds(1);
            var deviceClient = DeviceClient.CreateFromConnectionString(deviceConnectionString);

            while (true)
            {
                var receivedMessage = await deviceClient.ReceiveAsync();
                if (receivedMessage == null)
                {
                    await Task.Delay(oneSecond);
                    continue;
                }

                var messageData = Encoding.ASCII.GetString(receivedMessage.GetBytes());
                await deviceClient.CompleteAsync(receivedMessage);
                return messageData;
            }
        }

        public static async Task ReceiveMessagesFromDeviceAsync(CancellationToken cancelToken)
        {
            while (!cancelToken.IsCancellationRequested)
            {
                try
                {
                    string eventHubConnectionString = await IotHubConnection.GetEventHubsConnectionStringAsync(iotHubConnectionString);
                    await using var consumerClient = new EventHubConsumerClient(
                        EventHubConsumerClient.DefaultConsumerGroupName,
                        eventHubConnectionString);

                    await foreach (PartitionEvent partitionEvent in consumerClient.ReadEventsAsync(cancelToken))
                    {
                        if (partitionEvent.Data == null) continue;

                        string data = Encoding.UTF8.GetString(partitionEvent.Data.Body.ToArray());
                        Console.WriteLine($"Message received. Partition: {partitionEvent.Partition.PartitionId} Data: '{data}'");
                    }
                }
                catch (TimeoutException)
                {
                    Console.WriteLine($"{DateTime.Now} > Timeout receiving or connecting to Event Hub. Retrying after 1 second...");
                    await Task.Delay(1000);
                }
                catch (TaskCanceledException) 
                {
                    Console.WriteLine($"{DateTime.Now} > Receive events cancelled. Exiting..."); 
                    break; 
                } 
                catch (Exception ex)
                {
                    Console.WriteLine($"{DateTime.Now} > Error reading event: {ex.Message}. Retrying after 1 second...");
                    Task.Delay(1000);
                }
            }
        }
    }
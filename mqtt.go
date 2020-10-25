package main

import (
    "log"
    "strconv"
    "time"

    "github.com/goiiot/libmqtt"
)

type mqttClient struct {
    client libmqtt.Client
    err    error
}

var address string = "localhost"
var port int = 1883
var topics []*libmqtt.Topic

func setMQTTConParam(addr string, prt int) {
    address = addr
    port = prt
}

func setSubTopics(topicArr []string) {
    // Convert our args to libmqtt's Topic struct
    for _, topic := range topicArr {
        mqttTopic := &libmqtt.Topic{Name: topic, Qos: libmqtt.Qos0}
        topics = append(topics, mqttTopic)
    }
}

func startMQTTClient() {
    mc := mqttClient{}

    mc.client, mc.err = libmqtt.NewClient(
        // Use MQTT 3.1.1
        libmqtt.WithVersion(libmqtt.V311, true),
        // Enable keepalive (10s interval) with 20% tolerance
        libmqtt.WithKeepalive(10, 1.2),
        // Enable auto reconnect and set backoff strategy
        libmqtt.WithAutoReconnect(true),
        libmqtt.WithBackoffStrategy(time.Second, 5*time.Second, 1.2),
        libmqtt.WithRouter(libmqtt.NewRegexRouter()),
        libmqtt.WithConnHandleFunc(connHandler),
        libmqtt.WithNetHandleFunc(netHandler),
        libmqtt.WithSubHandleFunc(subHandler),
        libmqtt.WithPubHandleFunc(pubHandler),
        libmqtt.WithPersistHandleFunc(persistHandler),
    )

    // Set a handler for all topics
    mc.client.HandleTopic(".*", func(client libmqtt.Client,
        topic string,
        qos libmqtt.QosLevel,
        msg []byte) {
        log.Printf("[%v] message: %v", topic, string(msg))
    })

	// Connect to server
    fullAddress := address + ":" + strconv.Itoa(port)
    mc.err = mc.client.ConnectServer(fullAddress)

	mc.client.Wait()
}

func connHandler(client libmqtt.Client, server string, code byte, err error) {
    if err != nil {
        log.Printf("Failed connection to server [%v]: %v", server, err)
        return
    }

    if code != libmqtt.CodeSuccess {
        log.Printf("Server [%v] error; server code [%v]",
            server, code)
        return
    }

    go func() {
        // Subscribe to the user defined topics
        client.Subscribe(topics...)
    }()
}

func netHandler(client libmqtt.Client, server string, err error) {
	if err != nil {
        log.Printf("Connection error to server [%v]: %v",
            server,
            err)
    }   }

func persistHandler(client libmqtt.Client, packet libmqtt.Packet, err error) {
    if err != nil {
        log.Printf("Session persist error: %v", err)
    }
}

func subHandler(client libmqtt.Client, topics []*libmqtt.Topic, err error) {
    if err != nil {
        for _, t := range topics {
            log.Printf("Failed subscription to [%v]: %v", t.Name, err)
        }
    }
}

func pubHandler(client libmqtt.Client, topic string, err error) {
    if err != nil {
        log.Printf("Failed to publish to topic [%v]: %v", topic, err)
    }
}

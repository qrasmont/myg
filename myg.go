package main

import (
	"flag"
	"fmt"
	"os"
)

func commandeUsage() {
	fmt.Printf("Usage: myg [ OPTIONS ] TOPICS\n\n")
	fmt.Printf("Where TOPICS are the mqtt topics to subscribe to.\n\n")
	fmt.Printf("Where OPTIONS are:\n")
	flag.PrintDefaults()
}

func main() {
	// Define the command flags.
	address := flag.String("a", "localhost", "mqtt broker address")
	port := flag.Int("p", 1883, "mqtt broker port")

	// Set a custom usage message.
	flag.Usage = commandeUsage

	// Parse the flags.
	flag.Parse()

	// Check we have at least one topic to subscribe to.
	if len(os.Args) < 2 {
		fmt.Printf("I need at least one topic :(\n\n")
		commandeUsage()
		os.Exit(1)
	}

	setSubTopics(os.Args[1:]) // Slice to ignore our path
	setMQTTConParam(*address, *port)
	startMQTTClient()
}

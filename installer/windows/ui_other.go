//go:build !windows

package main

import "fmt"

func finish(_ bool, err error, messages ...string) {
	if err != nil {
		fmt.Println(err)
		return
	}
	for _, message := range messages {
		fmt.Println(message)
	}
}

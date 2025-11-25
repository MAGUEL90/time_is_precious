extends Node


signal dialouge_activated()
signal dialouge_deactivated()

func on_dialouge_activated():
	dialouge_activated.emit()

func on_dialouge_deactivated():
	dialouge_deactivated.emit()

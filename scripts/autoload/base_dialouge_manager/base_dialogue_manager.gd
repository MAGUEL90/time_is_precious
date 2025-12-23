extends Node


signal dialogue_activated()
signal dialogue_deactivated()
signal contract_activated()
signal contract_deactivated()

func on_dialogue_activated():
	dialogue_activated.emit()

func on_dialogue_deactivated():
	dialogue_deactivated.emit()

func on_contract_activated():
	contract_activated.emit()

func on_contract_deactivated():
	contract_deactivated.emit()

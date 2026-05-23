/*
    SPDX-FileCopyrightText: 2025 Yifan Zhu <fanzhuyifan@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    Singleton used to keep the password text in sync across StackView
    transitions, exactly as the stock Plasma 6 lock screen does.
*/

pragma Singleton

import QtQuick

QtObject {
    property string password
}

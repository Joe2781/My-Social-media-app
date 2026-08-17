package ghostdb

import "time"

// User model (partial)
type User struct {
	ID             int64     `db:"id" json:"id"`
	Username       string    `db:"username" json:"username"`
	DisplayName    string    `db:"display_name" json:"display_name"`
	Email          string    `db:"email" json:"email"`
	PasswordHash   string    `db:"password_hash" json:"-"`
	AvatarURL      string    `db:"avatar_url" json:"avatar_url"`
	Bio            string    `db:"bio" json:"bio"`
	PreferredLang  string    `db:"preferred_language" json:"preferred_language"`
	CreatedAt      time.Time `db:"created_at" json:"created_at"`
	UpdatedAt      time.Time `db:"updated_at" json:"updated_at"`
}

// DB is the GhostDB abstraction used across the backend.
type DB interface {
	Open(path string) error
	Ping() error
	Migrate() error
	Close() error

	CreateUser(username, displayName, email, password string) (*User, error)
	GetUserByUsername(username string) (*User, error)
}

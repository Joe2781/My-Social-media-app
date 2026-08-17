package sqliteadapter

import (
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/jmoiron/sqlx"
	"golang.org/x/crypto/bcrypt"

	"github.com/Joe2781/My-Social-media-app/backend/internal/db/ghostdb"
)

// SQLiteDB implements ghostdb.DB using SQLite.
type SQLiteDB struct {
	db *sqlx.DB
}

// New returns a SQLiteDB. openFunc is a helper to open DB connections in tests or different contexts.
func New(openFunc func(driverName, dataSourceName string) (*sqlx.DB, error)) (*SQLiteDB, error) {
	// open a temporary DB handle via provided openFunc when Open is called later
	_ = openFunc
	return &SQLiteDB{}, nil
}

func (s *SQLiteDB) Open(path string) error {
	if path == "" {
		return errors.New("empty path")
	}
	db, err := sqlx.Open("sqlite", path+"?_foreign_keys=1")
	if err != nil {
		return err
	}
	s.db = db
	return nil
}

func (s *SQLiteDB) Ping() error {
	if s.db == nil {
		return errors.New("db not opened")
	}
	return s.db.Ping()
}

func (s *SQLiteDB) Close() error {
	if s.db == nil {
		return nil
	}
	return s.db.Close()
}

func (s *SQLiteDB) Migrate() error {
	if s.db == nil {
		return errors.New("db not opened")
	}
	schema := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			username TEXT NOT NULL UNIQUE,
			display_name TEXT,
			email TEXT NOT NULL UNIQUE,
			password_hash TEXT NOT NULL,
			avatar_url TEXT,
			bio TEXT,
			preferred_language TEXT,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
		);`,
	}
	for _, q := range schema {
		if _, err := s.db.Exec(q); err != nil {
			return fmt.Errorf("migrate: %w", err)
		}
	}
	return nil
}

func (s *SQLiteDB) CreateUser(username, displayName, email, password string) (*ghostdb.User, error) {
	if s.db == nil {
		return nil, errors.New("db not opened")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}
	res, err := s.db.Exec(`INSERT INTO users (username, display_name, email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)`,
		username, displayName, email, string(hash), time.Now(), time.Now())
	if err != nil {
		return nil, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return nil, err
	}
	u := &ghostdb.User{
		ID:           id,
		Username:     username,
		DisplayName:  displayName,
		Email:        email,
		PasswordHash: string(hash),
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	return u, nil
}

func (s *SQLiteDB) GetUserByUsername(username string) (*ghostdb.User, error) {
	if s.db == nil {
		return nil, errors.New("db not opened")
	}
	u := &ghostdb.User{}
	if err := s.db.Get(u, "SELECT id, username, display_name, email, password_hash, avatar_url, bio, preferred_language, created_at, updated_at FROM users WHERE username = ?", username); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("user not found")
		}
		return nil, err
	}
	return u, nil
}

// ComparePassword compares a plaintext password with the stored hash.
func (u *ghostdb.User) ComparePassword(plain string) error {
	if u == nil {
		return errors.New("nil user")
	}
	return bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(plain))
}

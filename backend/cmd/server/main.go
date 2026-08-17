package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gorilla/mux"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jmoiron/sqlx"
	_ "modernc.org/sqlite"

	"github.com/Joe2781/My-Social-media-app/backend/internal/db/sqliteadapter"
)

var jwtSecret string
var db *sqliteadapter.SQLiteDB

func main() {
	jwtSecret = os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		log.Println("WARNING: JWT_SECRET not set. Using default development secret. Do NOT use in production.")
		jwtSecret = "dev_secret_change_me"
	}

	// initialize sqlite-backed GhostDB adapter
	dbPath := os.Getenv("DATABASE_PATH")
	if dbPath == "" {
		dbPath = "socialx_dev.db"
	}

	var err error
	db, err = sqliteadapter.New(sqlx.OpenDB)
	if err != nil {
		log.Fatalf("failed to initialize database adapter: %v", err)
	}

	// open connection
	if err := db.Open(dbPath); err != nil {
		log.Fatalf("failed to open database: %v", err)
	}

	// run migrations
	if err := db.Migrate(); err != nil {
		log.Fatalf("migration failed: %v", err)
	}

	r := mux.NewRouter()

	r.HandleFunc("/api/health", healthHandler).Methods("GET")
	r.HandleFunc("/api/ready", readyHandler).Methods("GET")

	r.HandleFunc("/api/register", registerHandler).Methods("POST")
	r.HandleFunc("/api/login", loginHandler).Methods("POST")

	// static file for simple testing
	r.PathPrefix("/").Handler(http.FileServer(http.Dir("./static")))

	addr := ":8080"
	if a := os.Getenv("PORT"); a != "" {
		addr = ":" + a
	}

	log.Printf("starting server on %s", addr)
	log.Fatal(http.ListenAndServe(addr, r))
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func readyHandler(w http.ResponseWriter, r *http.Request) {
	// simple readiness: DB reachable
	if err := db.Ping(); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("DB unreachable"))
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("READY"))
}

type registerReq struct {
	Username    string `json:"username"`
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"display_name"`
}

func registerHandler(w http.ResponseWriter, r *http.Request) {
	var req registerReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	if req.Username == "" || req.Password == "" || req.Email == "" {
		http.Error(w, "username, email and password are required", http.StatusBadRequest)
		return
	}

	u, err := db.CreateUser(req.Username, req.DisplayName, req.Email, req.Password)
	if err != nil {
		http.Error(w, fmt.Sprintf("create user: %v", err), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"id": u.ID, "username": u.Username})
}

type loginReq struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func loginHandler(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	user, err := db.GetUserByUsername(req.Username)
	if err != nil {
		http.Error(w, "invalid credentials", http.StatusUnauthorized)
		return
	}
	if err := user.ComparePassword(req.Password); err != nil {
		http.Error(w, "invalid credentials", http.StatusUnauthorized)
		return
	}
	// create JWT
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": user.ID,
		"exp": time.Now().Add(24 * time.Hour).Unix(),
		"iat": time.Now().Unix(),
	})
	signed, err := token.SignedString([]byte(jwtSecret))
	if err != nil {
		http.Error(w, "failed to sign token", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"token": signed, "user": map[string]any{"id": user.ID, "username": user.Username}})
}
